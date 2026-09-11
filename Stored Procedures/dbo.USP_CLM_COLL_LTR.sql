USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE dbo.USP_CLM_COLL_LTR
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* =============================================================
       DECLARE LOGGING VARIABLES
       ============================================================= */

    DECLARE
        @RUN_ID INT =
        (
            SELECT ISNULL(MAX(RUN_ID), 0)
            FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)
        ),
        @JOB_ID          VARCHAR(255) = 'COLLECTION_LETTER_PROCESS',
        @ERROR           INT = 0,
        @STEP_ID         INT = 0,
        @SYS_DEF_MSG     VARCHAR(5000),
        @SP_NAME         VARCHAR(255) = OBJECT_NAME(@@PROCID),
        @ROWS_PROCESSED  INT = 0,
        @STEP_DESC       VARCHAR(255),
        @STATUS_DESC     VARCHAR(255),
        @STATUS          VARCHAR(1);

    SET @RUN_ID = @RUN_ID + 1;


    BEGIN TRANSACTION;

    BEGIN TRY

        /* =========================================================
           STEP 1
           IDENTIFY ELIGIBLE RECOVERIES AND INSERT INTO
           CW_HEADER + CW_STATUS

           Eligible recovery:
             1. ACPR_STS = A
             2. MO
                  OR
                MR with EXCD THS/VXD/PHI
             3. Balance >= $25
             4. Not already in CW_HEADER

           Provider classification:
             PAR     = Network I/P, no 8017
             NON-PAR = Network O, no 8017
             VA      = Warning 8017
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC =
            'INSERT ELIGIBLE RECOVERIES INTO COLLECTION HEADER';


        ;WITH ELIGIBLE AS
        (
            SELECT
                A.ACPR_REF_ID,
                A.ACPR_TYPE,
                A.ACPR_SUB_TYPE,
                A.ACPR_CREATE_DT,
                SUM(ISNULL(A.ACPR_NET_AMT,0)) AS NET_AMT,

                MAX
                (
                    CASE
                        WHEN PRWM.WMDS_SEQ_NO = '8017'
                            THEN 1
                        ELSE 0
                    END
                ) AS IS_VA,

                MAX(C.CLCL_NTWK_IND) AS NETWORK_IND

            FROM FACETS.dbo.CMC_ACPR A

            INNER JOIN FACETS.dbo.CMC_CLOV O
                ON A.ACPR_REF_ID = O.ACPR_REF_ID

            INNER JOIN FACETS.dbo.CMC_CLCL C
                ON O.CLCL_ID = C.CLCL_ID

            LEFT JOIN FACETS.dbo.CMC_PRWM PRWM
                ON A.ACPR_PAYEE_ID = PRWM.PRPR_ID
               AND PRWM.WMDS_SEQ_NO = '8017'

            WHERE A.ACPR_STS = 'A'

              AND
              (
                    A.ACPR_TYPE = 'MO'

                    OR

                    (
                        A.ACPR_TYPE = 'MR'
                        AND A.EXCD_ID IN
                            ('THS','VXD','PHI')
                    )
              )

            GROUP BY
                A.ACPR_REF_ID,
                A.ACPR_TYPE,
                A.ACPR_SUB_TYPE,
                A.ACPR_CREATE_DT
        ),

        QUALIFIED AS
        (
            SELECT *
            FROM ELIGIBLE E

            WHERE E.NET_AMT >= 25

              AND
              (
                    /* PAR */
                    (
                        E.IS_VA = 0
                        AND E.NETWORK_IND IN ('I','P')
                        AND DATEDIFF
                            (
                                DAY,
                                E.ACPR_CREATE_DT,
                                GETDATE()
                            ) >= 1
                    )

                    OR

                    /* NON-PAR */
                    (
                        E.IS_VA = 0
                        AND E.NETWORK_IND = 'O'
                        AND DATEDIFF
                            (
                                DAY,
                                E.ACPR_CREATE_DT,
                                GETDATE()
                            ) >= 2
                    )

                    OR

                    /* VA - Step 1 initial extract rule */
                    (
                        E.IS_VA = 1
                        AND DATEDIFF
                            (
                                DAY,
                                E.ACPR_CREATE_DT,
                                GETDATE()
                            ) >= 2
                    )
              )
        )

        INSERT INTO dbo.CW_HEADER
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            ACPR_CREATE_DT,
            STATUS,
            UPDT_DTM,
            LAST_LTR_DT,
            ACPR_NET_AMT
        )

        SELECT
            Q.ACPR_REF_ID,
            Q.ACPR_TYPE,
            Q.ACPR_SUB_TYPE,
            Q.ACPR_CREATE_DT,
            'OPEN',
            GETDATE(),
            NULL,
            Q.NET_AMT

        FROM QUALIFIED Q

        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.CW_HEADER H

            WHERE H.ACPR_REF_ID   = Q.ACPR_REF_ID
              AND H.ACPR_TYPE     = Q.ACPR_TYPE
              AND H.ACPR_SUB_TYPE = Q.ACPR_SUB_TYPE
        );


        SET @ROWS_PROCESSED = @@ROWCOUNT;


        /* =========================================================
           Insert corresponding OPEN history
           ========================================================= */

        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            H.ACPR_REF_ID,
            H.ACPR_TYPE,
            H.ACPR_SUB_TYPE,
            'OPEN',
            GETDATE()

        FROM dbo.CW_HEADER H

        WHERE H.STATUS = 'OPEN'

          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.CW_STATUS S

              WHERE S.ACPR_REF_ID   = H.ACPR_REF_ID
                AND S.ACPR_TYPE     = H.ACPR_TYPE
                AND S.ACPR_SUB_TYPE = H.ACPR_SUB_TYPE
                AND S.STATUS        = 'OPEN'
          );


        SET @STATUS_DESC = @STEP_DESC + ' COMPLETED';
        SET @STATUS = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID          = @RUN_ID,
             @JOB_ID          = @JOB_ID,
             @STATUS_DESC     = @STATUS_DESC,
             @SYS_DEF_MSG     = @SYS_DEF_MSG,
             @STEP_ID         = @STEP_ID,
             @SP_NAME         = @SP_NAME,
             @ERROR           = @ERROR,
             @ROWS_PROCESSED  = @ROWS_PROCESSED,
             @STATUS          = @STATUS;



        /* =========================================================
           STEP 2A
           UPDATE CURRENT NET AMOUNT
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC =
            'UPDATE CURRENT COLLECTION RECOVERY BALANCE';


        UPDATE H

        SET
            H.ACPR_NET_AMT = ISNULL(A.NET_AMT,0),
            H.UPDT_DTM = GETDATE()

        FROM dbo.CW_HEADER H

        INNER JOIN
        (
            SELECT
                ACPR_REF_ID,
                ACPR_TYPE,
                ACPR_SUB_TYPE,
                SUM(ISNULL(ACPR_NET_AMT,0)) AS NET_AMT

            FROM FACETS.dbo.CMC_ACPR

            GROUP BY
                ACPR_REF_ID,
                ACPR_TYPE,
                ACPR_SUB_TYPE

        ) A
            ON H.ACPR_REF_ID   = A.ACPR_REF_ID
           AND H.ACPR_TYPE     = A.ACPR_TYPE
           AND H.ACPR_SUB_TYPE = A.ACPR_SUB_TYPE

        WHERE H.STATUS IN
              ('OPEN','HOLD','REOPEN');


        SET @ROWS_PROCESSED = @@ROWCOUNT;
        SET @STATUS_DESC = @STEP_DESC + ' COMPLETED';
        SET @STATUS = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID,
             @JOB_ID,
             @STATUS_DESC,
             @SYS_DEF_MSG,
             @STEP_ID,
             @SP_NAME,
             @ERROR,
             @ROWS_PROCESSED,
             @STATUS;



        /* =========================================================
           STEP 2B
           VOID RECOVERY

           ACPR_STS = V
              ↓
           CW_STATUS = VOID
           CW_HEADER = VOID
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC =
            'VOID COLLECTION RECOVERIES';


        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            H.ACPR_REF_ID,
            H.ACPR_TYPE,
            H.ACPR_SUB_TYPE,
            'VOID',
            GETDATE()

        FROM dbo.CW_HEADER H

        INNER JOIN FACETS.dbo.CMC_ACPR A
            ON H.ACPR_REF_ID   = A.ACPR_REF_ID
           AND H.ACPR_TYPE     = A.ACPR_TYPE
           AND H.ACPR_SUB_TYPE = A.ACPR_SUB_TYPE

        WHERE H.STATUS IN ('OPEN','HOLD','REOPEN')
          AND A.ACPR_STS = 'V';


        SET @ROWS_PROCESSED = @@ROWCOUNT;


        UPDATE H

        SET
            H.STATUS = 'VOID',
            H.UPDT_DTM = GETDATE()

        FROM dbo.CW_HEADER H

        INNER JOIN FACETS.dbo.CMC_ACPR A
            ON H.ACPR_REF_ID   = A.ACPR_REF_ID
           AND H.ACPR_TYPE     = A.ACPR_TYPE
           AND H.ACPR_SUB_TYPE = A.ACPR_SUB_TYPE

        WHERE H.STATUS IN ('OPEN','HOLD','REOPEN')
          AND A.ACPR_STS = 'V';


        SET @STATUS_DESC = @STEP_DESC + ' COMPLETED';
        SET @STATUS = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID,
             @JOB_ID,
             @STATUS_DESC,
             @SYS_DEF_MSG,
             @STEP_ID,
             @SP_NAME,
             @ERROR,
             @ROWS_PROCESSED,
             @STATUS;



        /* =========================================================
           STEP 2C
           CLOSE FULLY RECOVERED RECORDS

           NET AMOUNT = 0
                ↓
           STATUS = CLOSE
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC =
            'CLOSE FULLY RECOVERED COLLECTIONS';


        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            H.ACPR_REF_ID,
            H.ACPR_TYPE,
            H.ACPR_SUB_TYPE,
            'CLOSE',
            GETDATE()

        FROM dbo.CW_HEADER H

        WHERE H.STATUS IN ('OPEN','HOLD','REOPEN')
          AND ISNULL(H.ACPR_NET_AMT,0) = 0;


        SET @ROWS_PROCESSED = @@ROWCOUNT;


        UPDATE dbo.CW_HEADER

        SET
            STATUS = 'CLOSE',
            UPDT_DTM = GETDATE()

        WHERE STATUS IN ('OPEN','HOLD','REOPEN')
          AND ISNULL(ACPR_NET_AMT,0) = 0;


        SET @STATUS_DESC = @STEP_DESC + ' COMPLETED';
        SET @STATUS = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID,
             @JOB_ID,
             @STATUS_DESC,
             @SYS_DEF_MSG,
             @STEP_ID,
             @SP_NAME,
             @ERROR,
             @ROWS_PROCESSED,
             @STATUS;



        /* =========================================================
           STEP 2D
           PLACE RECOVERY ON HOLD

           Hold condition:
              ACRH_EVENT_TYPE = W
              ACRH_MCTR_RSN   = HOLD
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC =
            'PLACE COLLECTION RECOVERIES ON HOLD';


        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            H.ACPR_REF_ID,
            H.ACPR_TYPE,
            H.ACPR_SUB_TYPE,
            'HOLD',
            GETDATE()

        FROM dbo.CW_HEADER H

        WHERE H.STATUS IN ('OPEN','REOPEN')

          AND EXISTS
          (
              SELECT 1

              FROM FACETS.dbo.CMC_ACRH R

              WHERE R.ACPR_REF_ID   = H.ACPR_REF_ID
                AND R.ACPR_SUB_TYPE = H.ACPR_SUB_TYPE
                AND R.ACRH_EVENT_TYPE = 'W'
                AND LTRIM(RTRIM(R.ACRH_MCTR_RSN)) = 'HOLD'
          );


        SET @ROWS_PROCESSED = @@ROWCOUNT;


        UPDATE H

        SET
            H.STATUS = 'HOLD',
            H.UPDT_DTM = GETDATE()

        FROM dbo.CW_HEADER H

        WHERE H.STATUS IN ('OPEN','REOPEN')

          AND EXISTS
          (
              SELECT 1

              FROM FACETS.dbo.CMC_ACRH R

              WHERE R.ACPR_REF_ID   = H.ACPR_REF_ID
                AND R.ACPR_SUB_TYPE = H.ACPR_SUB_TYPE
                AND R.ACRH_EVENT_TYPE = 'W'
                AND LTRIM(RTRIM(R.ACRH_MCTR_RSN)) = 'HOLD'
          );


        SET @STATUS_DESC = @STEP_DESC + ' COMPLETED';
        SET @STATUS = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID,
             @JOB_ID,
             @STATUS_DESC,
             @SYS_DEF_MSG,
             @STEP_ID,
             @SP_NAME,
             @ERROR,
             @ROWS_PROCESSED,
             @STATUS;



        /* =========================================================
           STEP 2E
           REMOVE HOLD / REOPEN

           Requirement:
           Current status HOLD and no HOLD ACRH record
             → Insert "Hold Removed"
             → Header status REOPEN

           NOTE:
           This follows the workbook literally.
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC =
            'REOPEN COLLECTION RECOVERIES AFTER HOLD REMOVAL';


        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            H.ACPR_REF_ID,
            H.ACPR_TYPE,
            H.ACPR_SUB_TYPE,
            'HOLD REMOVED',
            GETDATE()

        FROM dbo.CW_HEADER H

        WHERE H.STATUS = 'HOLD'

          AND NOT EXISTS
          (
              SELECT 1

              FROM FACETS.dbo.CMC_ACRH R

              WHERE R.ACPR_REF_ID   = H.ACPR_REF_ID
                AND R.ACPR_SUB_TYPE = H.ACPR_SUB_TYPE
                AND R.ACRH_EVENT_TYPE = 'W'
                AND LTRIM(RTRIM(R.ACRH_MCTR_RSN)) = 'HOLD'
          );


        SET @ROWS_PROCESSED = @@ROWCOUNT;


        UPDATE H

        SET
            H.STATUS = 'REOPEN',
            H.UPDT_DTM = GETDATE()

        FROM dbo.CW_HEADER H

        WHERE H.STATUS = 'HOLD'

          AND NOT EXISTS
          (
              SELECT 1

              FROM FACETS.dbo.CMC_ACRH R

              WHERE R.ACPR_REF_ID   = H.ACPR_REF_ID
                AND R.ACPR_SUB_TYPE = H.ACPR_SUB_TYPE
                AND R.ACRH_EVENT_TYPE = 'W'
                AND LTRIM(RTRIM(R.ACRH_MCTR_RSN)) = 'HOLD'
          );


        SET @STATUS_DESC = @STEP_DESC + ' COMPLETED';
        SET @STATUS = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID,
             @JOB_ID,
             @STATUS_DESC,
             @SYS_DEF_MSG,
             @STEP_ID,
             @SP_NAME,
             @ERROR,
             @ROWS_PROCESSED,
             @STATUS;



        /* =========================================================
           STEP 3
           IDENTIFY LETTERS THAT SHOULD BE GENERATED

           This procedure returns the qualifying rows.

           LAST_LTR_DT:
              NULL     = Initial Letter
              NOT NULL = Follow-up Letter
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;
        SET @STEP_DESC =
            'EXTRACT ELIGIBLE COLLECTION LETTER DATA';


        IF OBJECT_ID('tempdb..#LETTER_DATA') IS NOT NULL
            DROP TABLE #LETTER_DATA;


        SELECT
            H.ACPR_REF_ID,
            H.ACPR_TYPE,
            H.ACPR_SUB_TYPE,
            H.ACPR_CREATE_DT,
            H.ACPR_NET_AMT,

            O.CLCL_ID,
            C.CLCL_SUB_TYPE,
            A.ACPR_PAYEE_ID AS PRPR_ID,

            P.PRPR_NAME,
            P.PRPR_ADD1,
            P.PRPR_ADD2,
            P.PRPR_CITY,
            P.PRPR_STATE,
            P.PRPR_CNTRY,

            H.LAST_LTR_DT,

            CASE
                WHEN VA.PRPR_ID IS NOT NULL
                    THEN 'VA'

                WHEN C.CLCL_NTWK_IND IN ('I','P')
                    THEN 'PAR'

                WHEN C.CLCL_NTWK_IND = 'O'
                    THEN 'NON-PAR'

            END AS PROVIDER_TYPE,

            CASE
                WHEN H.LAST_LTR_DT IS NULL
                    THEN 'INITIAL LETTER'
                ELSE 'FOLLOW UP LETTER'
            END AS LETTER_TYPE

        INTO #LETTER_DATA

        FROM dbo.CW_HEADER H

        INNER JOIN FACETS.dbo.CMC_ACPR A
            ON H.ACPR_REF_ID   = A.ACPR_REF_ID
           AND H.ACPR_TYPE     = A.ACPR_TYPE
           AND H.ACPR_SUB_TYPE = A.ACPR_SUB_TYPE

        INNER JOIN FACETS.dbo.CMC_CLOV O
            ON A.ACPR_REF_ID = O.ACPR_REF_ID

        INNER JOIN FACETS.dbo.CMC_CLCL C
            ON O.CLCL_ID = C.CLCL_ID

        INNER JOIN FACETS.dbo.CMC_PRPR P
            ON A.ACPR_PAYEE_ID = P.PRPR_ID

        OUTER APPLY
        (
            SELECT TOP 1
                W.PRPR_ID

            FROM FACETS.dbo.CMC_PRWM W

            WHERE W.PRPR_ID = A.ACPR_PAYEE_ID
              AND W.WMDS_SEQ_NO = '8017'

        ) VA

        WHERE H.STATUS IN ('OPEN','REOPEN')

          AND H.ACPR_NET_AMT >= 25

          AND
          (
              /* =============================================
                 VA
                 Initial letter: Day 1
                 Follow-up: Every 2 days
                 Stop: Day 5
                 ============================================= */

              (
                  VA.PRPR_ID IS NOT NULL

                  AND DATEDIFF
                      (
                          DAY,
                          H.ACPR_CREATE_DT,
                          GETDATE()
                      ) < 5

                  AND
                  (
                      (
                          H.LAST_LTR_DT IS NULL

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.ACPR_CREATE_DT,
                                  GETDATE()
                              ) >= 1
                      )

                      OR

                      (
                          H.LAST_LTR_DT IS NOT NULL

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.LAST_LTR_DT,
                                  GETDATE()
                              ) >= 2
                      )
                  )
              )


              OR


              /* =============================================
                 NON-PAR
                 Initial: Day 2
                 Follow-up: Every 2 days
                 Stop: Day 6
                 ============================================= */

              (
                  VA.PRPR_ID IS NULL
                  AND C.CLCL_NTWK_IND = 'O'

                  AND DATEDIFF
                      (
                          DAY,
                          H.ACPR_CREATE_DT,
                          GETDATE()
                      ) < 6

                  AND
                  (
                      (
                          H.LAST_LTR_DT IS NULL

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.ACPR_CREATE_DT,
                                  GETDATE()
                              ) >= 2
                      )

                      OR

                      (
                          H.LAST_LTR_DT IS NOT NULL

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.LAST_LTR_DT,
                                  GETDATE()
                              ) >= 2
                      )
                  )
              )


              OR


              /* =============================================
                 PAR

                 Day 1:
                    Minimum $25

                 Before Day 7:
                    Every 2 days, minimum $25

                 Day 7 onward:
                    Minimum $50

                 Day 10:
                    Stop
                 ============================================= */

              (
                  VA.PRPR_ID IS NULL
                  AND C.CLCL_NTWK_IND IN ('I','P')

                  AND DATEDIFF
                      (
                          DAY,
                          H.ACPR_CREATE_DT,
                          GETDATE()
                      ) < 10

                  AND
                  (
                      /* Initial letter */

                      (
                          H.LAST_LTR_DT IS NULL

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.ACPR_CREATE_DT,
                                  GETDATE()
                              ) >= 1

                          AND H.ACPR_NET_AMT >= 25
                      )

                      OR

                      /* Follow-up before Day 7 */

                      (
                          H.LAST_LTR_DT IS NOT NULL

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.ACPR_CREATE_DT,
                                  GETDATE()
                              ) < 7

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.LAST_LTR_DT,
                                  GETDATE()
                              ) >= 2

                          AND H.ACPR_NET_AMT >= 25
                      )

                      OR

                      /* Follow-up Day 7 through Day 9 */

                      (
                          H.LAST_LTR_DT IS NOT NULL

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.ACPR_CREATE_DT,
                                  GETDATE()
                              ) >= 7

                          AND DATEDIFF
                              (
                                  DAY,
                                  H.LAST_LTR_DT,
                                  GETDATE()
                              ) >= 2

                          AND H.ACPR_NET_AMT >= 50
                      )
                  )
              )
          );


        SET @ROWS_PROCESSED = @@ROWCOUNT;



        /* =========================================================
           INSERT LETTER STATUS HISTORY
           ========================================================= */

        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            LETTER_TYPE,
            GETDATE()

        FROM #LETTER_DATA;



        /* =========================================================
           UPDATE LAST LETTER DATE

           Requirement says follow-up calculation must use the
           previous generated letter date.
           ========================================================= */

        UPDATE H

        SET
            H.LAST_LTR_DT = GETDATE(),
            H.UPDT_DTM = GETDATE()

        FROM dbo.CW_HEADER H

        INNER JOIN #LETTER_DATA L
            ON H.ACPR_REF_ID   = L.ACPR_REF_ID
           AND H.ACPR_TYPE     = L.ACPR_TYPE
           AND H.ACPR_SUB_TYPE = L.ACPR_SUB_TYPE;



        /* =========================================================
           STEP 3B
           STOP LETTERS

           PAR:
              Day >= 7 and balance < $50
              OR Day >= 10

           NON-PAR:
              Day >= 6

           VA:
              Day >= 5
           ========================================================= */

        ;WITH STOP_DATA AS
        (
            SELECT DISTINCT
                H.ACPR_REF_ID,
                H.ACPR_TYPE,
                H.ACPR_SUB_TYPE

            FROM dbo.CW_HEADER H

            INNER JOIN FACETS.dbo.CMC_ACPR A
                ON H.ACPR_REF_ID   = A.ACPR_REF_ID
               AND H.ACPR_TYPE     = A.ACPR_TYPE
               AND H.ACPR_SUB_TYPE = A.ACPR_SUB_TYPE

            INNER JOIN FACETS.dbo.CMC_CLOV O
                ON A.ACPR_REF_ID = O.ACPR_REF_ID

            INNER JOIN FACETS.dbo.CMC_CLCL C
                ON O.CLCL_ID = C.CLCL_ID

            WHERE H.STATUS IN ('OPEN','REOPEN')

              AND
              (
                  /* VA stop at Day 5 */

                  (
                      EXISTS
                      (
                          SELECT 1
                          FROM FACETS.dbo.CMC_PRWM W

                          WHERE W.PRPR_ID =
                                A.ACPR_PAYEE_ID

                            AND W.WMDS_SEQ_NO = '8017'
                      )

                      AND DATEDIFF
                          (
                              DAY,
                              H.ACPR_CREATE_DT,
                              GETDATE()
                          ) >= 5
                  )


                  OR


                  /* NON-PAR stop Day 6 */

                  (
                      NOT EXISTS
                      (
                          SELECT 1
                          FROM FACETS.dbo.CMC_PRWM W

                          WHERE W.PRPR_ID =
                                A.ACPR_PAYEE_ID

                            AND W.WMDS_SEQ_NO = '8017'
                      )

                      AND C.CLCL_NTWK_IND = 'O'

                      AND DATEDIFF
                          (
                              DAY,
                              H.ACPR_CREATE_DT,
                              GETDATE()
                          ) >= 6
                  )


                  OR


                  /* PAR stop rules */

                  (
                      NOT EXISTS
                      (
                          SELECT 1
                          FROM FACETS.dbo.CMC_PRWM W

                          WHERE W.PRPR_ID =
                                A.ACPR_PAYEE_ID

                            AND W.WMDS_SEQ_NO = '8017'
                      )

                      AND C.CLCL_NTWK_IND IN ('I','P')

                      AND
                      (
                          DATEDIFF
                          (
                              DAY,
                              H.ACPR_CREATE_DT,
                              GETDATE()
                          ) >= 10

                          OR

                          (
                              DATEDIFF
                              (
                                  DAY,
                                  H.ACPR_CREATE_DT,
                                  GETDATE()
                              ) >= 7

                              AND H.ACPR_NET_AMT < 50
                          )
                      )
                  )
              )
        )

        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            'STOP LETTERS',
            GETDATE()

        FROM STOP_DATA;


        /* Update Header to CLOSE */

        ;WITH STOP_DATA AS
        (
            SELECT DISTINCT
                H.ACPR_REF_ID,
                H.ACPR_TYPE,
                H.ACPR_SUB_TYPE

            FROM dbo.CW_HEADER H

            INNER JOIN FACETS.dbo.CMC_ACPR A
                ON H.ACPR_REF_ID   = A.ACPR_REF_ID
               AND H.ACPR_TYPE     = A.ACPR_TYPE
               AND H.ACPR_SUB_TYPE = A.ACPR_SUB_TYPE

            INNER JOIN FACETS.dbo.CMC_CLOV O
                ON A.ACPR_REF_ID = O.ACPR_REF_ID

            INNER JOIN FACETS.dbo.CMC_CLCL C
                ON O.CLCL_ID = C.CLCL_ID

            WHERE H.STATUS IN ('OPEN','REOPEN')

              AND
              (
                  (
                      EXISTS
                      (
                          SELECT 1
                          FROM FACETS.dbo.CMC_PRWM W
                          WHERE W.PRPR_ID =
                                A.ACPR_PAYEE_ID
                            AND W.WMDS_SEQ_NO = '8017'
                      )

                      AND DATEDIFF
                          (
                              DAY,
                              H.ACPR_CREATE_DT,
                              GETDATE()
                          ) >= 5
                  )

                  OR

                  (
                      NOT EXISTS
                      (
                          SELECT 1
                          FROM FACETS.dbo.CMC_PRWM W
                          WHERE W.PRPR_ID =
                                A.ACPR_PAYEE_ID
                            AND W.WMDS_SEQ_NO = '8017'
                      )

                      AND C.CLCL_NTWK_IND = 'O'

                      AND DATEDIFF
                          (
                              DAY,
                              H.ACPR_CREATE_DT,
                              GETDATE()
                          ) >= 6
                  )

                  OR

                  (
                      NOT EXISTS
                      (
                          SELECT 1
                          FROM FACETS.dbo.CMC_PRWM W
                          WHERE W.PRPR_ID =
                                A.ACPR_PAYEE_ID
                            AND W.WMDS_SEQ_NO = '8017'
                      )

                      AND C.CLCL_NTWK_IND IN ('I','P')

                      AND
                      (
                          DATEDIFF
                          (
                              DAY,
                              H.ACPR_CREATE_DT,
                              GETDATE()
                          ) >= 10

                          OR

                          (
                              DATEDIFF
                              (
                                  DAY,
                                  H.ACPR_CREATE_DT,
                                  GETDATE()
                              ) >= 7

                              AND H.ACPR_NET_AMT < 50
                          )
                      )
                  )
              )
        )

        UPDATE H

        SET
            H.STATUS = 'CLOSE',
            H.UPDT_DTM = GETDATE()

        FROM dbo.CW_HEADER H

        INNER JOIN STOP_DATA S
            ON H.ACPR_REF_ID   = S.ACPR_REF_ID
           AND H.ACPR_TYPE     = S.ACPR_TYPE
           AND H.ACPR_SUB_TYPE = S.ACPR_SUB_TYPE;



        SET @STATUS_DESC = @STEP_DESC + ' COMPLETED';
        SET @STATUS = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID,
             @JOB_ID,
             @STATUS_DESC,
             @SYS_DEF_MSG,
             @STEP_ID,
             @SP_NAME,
             @ERROR,
             @ROWS_PROCESSED,
             @STATUS;



        COMMIT TRANSACTION;


        /* =========================================================
           RETURN LETTER DATA

           This result can later be transformed to XML.
           ========================================================= */

        SELECT *
        FROM #LETTER_DATA
        ORDER BY
            PROVIDER_TYPE,
            ACPR_REF_ID;


    END TRY


    BEGIN CATCH

        SELECT
            @ERROR = ERROR_NUMBER(),
            @SYS_DEF_MSG = ERROR_MESSAGE(),
            @STATUS_DESC =
                ISNULL(@STEP_DESC,
                       'COLLECTION LETTER PROCESS')
                + ' FAILED.',
            @STATUS = 'E';


        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @RUN_ID          = @RUN_ID,
             @JOB_ID          = @JOB_ID,
             @STATUS_DESC     = @STATUS_DESC,
             @SYS_DEF_MSG     = @SYS_DEF_MSG,
             @STEP_ID         = @STEP_ID,
             @SP_NAME         = @SP_NAME,
             @ERROR           = @ERROR,
             @ROWS_PROCESSED  = @ROWS_PROCESSED,
             @STATUS          = @STATUS;


        THROW;

    END CATCH;

END
GO

-- Execution Call

EXEC dbo.USP_CLM_COLL_LTR;



-- Inspecting Header and Status
SELECT *
FROM dbo.CW_HEADER
ORDER BY UPDT_DTM DESC;

SELECT *
FROM dbo.CW_STATUS
ORDER BY UPDT_DTM DESC;
