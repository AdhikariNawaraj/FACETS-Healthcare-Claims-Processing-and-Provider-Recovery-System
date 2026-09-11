USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE dbo.USP_CLM_PYMT_WROFF
AS
/*
=====================================================================
 PROCEDURE : USP_CLM_PYMT_WROFF
 PURPOSE   : Write off eligible provider recovery balances.

 PROCESS
 --------------------------------------------------------------------
 1. Identify eligible collection records.
 2. Determine provider-level outstanding balance.
 3. Write off eligible remaining ACPR_NET_AMT.
 4. Add write-off amount to ACPR_WOFF_AMT.
 5. Set ACPR_NET_AMT = 0.
 6. Set ACPR_STS = 'I'.
 7. Insert write-off history into CMC_ACRH.
 8. Insert WRITE-OFF status into CW_STATUS.
 9. Close the corresponding CW_HEADER record.
=====================================================================
*/
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;


    /* =============================================================
       DECLARE LOGGING VARIABLES
       ============================================================= */

    DECLARE
        @RUN_ID INT =
        (
            SELECT ISNULL(MAX(RUN_ID),0)
            FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)
        ),

        @JOB_ID             VARCHAR(255) = 'CLCL_PROCESSING',
        @ERROR              INT = 0,
        @STEP_ID            INT = 0,
        @SYS_DEF_MSG        VARCHAR(5000),
        @SP_NAME            VARCHAR(255) = OBJECT_NAME(@@PROCID),
        @ROWS_PROCESSED     INT = 0,
        @STEP_DESC          VARCHAR(255),
        @STATUS_DESC        VARCHAR(255),
        @STATUS             VARCHAR(1);


    SET @RUN_ID = @RUN_ID + 1;


    BEGIN TRANSACTION;

    BEGIN TRY


        /* =========================================================
           STEP 1
           IDENTIFY ELIGIBLE WRITE-OFF RECORDS

           Requirement:
           Provider-level outstanding recovery balance < $100.

           Only collection records that have reached the end of
           collection activity are considered.

           The temp table stores the exact ACPR rows that will
           be written off during this execution.
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'IDENTIFY ELIGIBLE PROVIDER RECOVERIES FOR WRITE OFF';


        IF OBJECT_ID('tempdb..#WRITE_OFF_DATA') IS NOT NULL
            DROP TABLE #WRITE_OFF_DATA;


        ;WITH PROVIDER_BALANCE AS
        (
            SELECT
                A.ACPR_PAYEE_ID AS PRPR_ID,

                SUM
                (
                    ISNULL(A.ACPR_NET_AMT,0)
                ) AS PROVIDER_NET_AMT

            FROM FACETS.dbo.CMC_ACPR A

            INNER JOIN dbo.CW_HEADER H
                ON A.ACPR_REF_ID   = H.ACPR_REF_ID
               AND A.ACPR_TYPE     = H.ACPR_TYPE
               AND A.ACPR_SUB_TYPE = H.ACPR_SUB_TYPE

            WHERE A.ACPR_STS = 'A'

              AND ISNULL(A.ACPR_NET_AMT,0) > 0

              /*
                 Collection letter processing has completed.
              */
              AND H.STATUS = 'CLOSE'

            GROUP BY
                A.ACPR_PAYEE_ID
        )

        SELECT
            A.ACPR_REF_ID,
            A.ACPR_TYPE,
            A.ACPR_SUB_TYPE,
            A.ACPR_PAYEE_ID AS PRPR_ID,

            A.ACPR_ORIG_AMT,
            ISNULL(A.ACPR_RECOV_AMT,0)
                AS ACPR_RECOV_AMT,

            ISNULL(A.ACPR_WOFF_AMT,0)
                AS CURRENT_WOFF_AMT,

            ISNULL(A.ACPR_NET_AMT,0)
                AS WRITE_OFF_AMT,

            PB.PROVIDER_NET_AMT

        INTO #WRITE_OFF_DATA

        FROM FACETS.dbo.CMC_ACPR A

        INNER JOIN dbo.CW_HEADER H
            ON A.ACPR_REF_ID   = H.ACPR_REF_ID
           AND A.ACPR_TYPE     = H.ACPR_TYPE
           AND A.ACPR_SUB_TYPE = H.ACPR_SUB_TYPE

        INNER JOIN PROVIDER_BALANCE PB
            ON A.ACPR_PAYEE_ID = PB.PRPR_ID

        WHERE A.ACPR_STS = 'A'

          AND ISNULL(A.ACPR_NET_AMT,0) > 0

          AND H.STATUS = 'CLOSE'

          /*
             Provider-level write-off threshold
          */
          AND PB.PROVIDER_NET_AMT < 100;


        SET @ROWS_PROCESSED = @@ROWCOUNT;

        SET @STATUS_DESC =
            @STEP_DESC + ' COMPLETED';

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
           STEP 2
           UPDATE CMC_ACPR

           Existing WOFF + remaining NET = new WOFF
           NET = 0
           STATUS = I
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'UPDATE ACPR AMOUNTS FOR PROVIDER WRITE OFF';


        UPDATE A

        SET
            A.ACPR_WOFF_AMT =
                ISNULL(A.ACPR_WOFF_AMT,0)
                + W.WRITE_OFF_AMT,

            A.ACPR_NET_AMT = 0,

            A.ACPR_STS = 'I'

        FROM FACETS.dbo.CMC_ACPR A

        INNER JOIN #WRITE_OFF_DATA W
            ON A.ACPR_REF_ID   = W.ACPR_REF_ID
           AND A.ACPR_TYPE     = W.ACPR_TYPE
           AND A.ACPR_SUB_TYPE = W.ACPR_SUB_TYPE;


        SET @ROWS_PROCESSED = @@ROWCOUNT;

        SET @STATUS_DESC =
            @STEP_DESC + ' COMPLETED';

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
           STEP 3
           INSERT WRITE-OFF HISTORY INTO CMC_ACRH

           Proposed:
              Event Type = W
              Reason     = SWOF

           SWOF = Small Write-Off
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'INSERT PROVIDER WRITE OFF HISTORY INTO CMC_ACRH';


        INSERT INTO FACETS.dbo.CMC_ACRH
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            ACRH_CREATE_DT,
            ACRH_EVENT_TYPE,
            ACRH_AMT,
            ACRH_MCTR_RSN
        )

        SELECT
            W.ACPR_REF_ID,
            W.ACPR_TYPE,
            W.ACPR_SUB_TYPE,
            GETDATE(),

            /* Write-off */
            'W',

            W.WRITE_OFF_AMT,

            /* Small Write-Off */
            'SWOF'

        FROM #WRITE_OFF_DATA W;


        SET @ROWS_PROCESSED = @@ROWCOUNT;

        SET @STATUS_DESC =
            @STEP_DESC + ' COMPLETED';

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
           STEP 4
           INSERT WRITE-OFF STATUS INTO CW_STATUS
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'INSERT WRITE OFF STATUS INTO COLLECTION HISTORY';


        INSERT INTO dbo.CW_STATUS
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            STATUS,
            UPDT_DTM
        )

        SELECT
            W.ACPR_REF_ID,
            W.ACPR_TYPE,
            W.ACPR_SUB_TYPE,
            'WRITE-OFF',
            GETDATE()

        FROM #WRITE_OFF_DATA W;


        SET @ROWS_PROCESSED = @@ROWCOUNT;

        SET @STATUS_DESC =
            @STEP_DESC + ' COMPLETED';

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
           STEP 5
           CLOSE COLLECTION HEADER

           After write-off:
              ACPR_NET_AMT = 0
              Collection is complete
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'CLOSE COLLECTION HEADER AFTER WRITE OFF';


        UPDATE H

        SET
            H.ACPR_NET_AMT = 0,
            H.STATUS = 'CLOSE',
            H.UPDT_DTM = GETDATE()

        FROM dbo.CW_HEADER H

        INNER JOIN #WRITE_OFF_DATA W
            ON H.ACPR_REF_ID   = W.ACPR_REF_ID
           AND H.ACPR_TYPE     = W.ACPR_TYPE
           AND H.ACPR_SUB_TYPE = W.ACPR_SUB_TYPE;


        SET @ROWS_PROCESSED = @@ROWCOUNT;

        SET @STATUS_DESC =
            @STEP_DESC + ' COMPLETED';

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



        COMMIT TRANSACTION;


        /* =========================================================
           RETURN WRITE-OFF SUMMARY
           ========================================================= */

        SELECT
            PRPR_ID,
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE,
            ACPR_ORIG_AMT,
            ACPR_RECOV_AMT,
            CURRENT_WOFF_AMT,
            WRITE_OFF_AMT,
            PROVIDER_NET_AMT,

            'WRITE-OFF COMPLETED'
                AS WRITE_OFF_STATUS

        FROM #WRITE_OFF_DATA

        ORDER BY
            PRPR_ID,
            ACPR_REF_ID;


    END TRY


    BEGIN CATCH

        SELECT
            @ERROR = ERROR_NUMBER(),

            @SYS_DEF_MSG = ERROR_MESSAGE(),

            @STATUS_DESC =
                ISNULL
                (
                    @STEP_DESC,
                    'PROVIDER WRITE OFF PROCESS'
                )
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

-- Execute the Procedure
EXEC dbo.USP_CLM_PYMT_WROFF;

-- Verify
SELECT
    ACPR_REF_ID,
    ACPR_PAYEE_ID,
    ACPR_ORIG_AMT,
    ACPR_RECOV_AMT,
    ACPR_WOFF_AMT,
    ACPR_NET_AMT,
    ACPR_STS
FROM FACETS.dbo.CMC_ACPR
ORDER BY ACPR_CREATE_DT DESC;


SELECT *
FROM FACETS.dbo.CMC_ACRH
WHERE ACRH_MCTR_RSN = 'SWOF'
ORDER BY ACRH_CREATE_DT DESC;


SELECT *
FROM FACETS_Custom.dbo.CW_STATUS
ORDER BY UPDT_DTM DESC;


SELECT *
FROM FACETS_Custom.dbo.CW_HEADER
ORDER BY UPDT_DTM DESC;
