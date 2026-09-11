USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_SVCDT_VAL]
AS

/*
    CREATED BY      - Nawaraj Adhikari
    CREATION DATE   - 09/01/2026
    DESCRIPTION     - VALIDATE SERVICE DATES FOR CLAIMS DURING
                      CLAIM PREPROCESSING

    BUSINESS RULES
    ---------------------------------------------------------------
    1. Process only eligible submitted claims.
    2. Member Match must already be successful.
    3. Provider Match must already be successful.
    4. Already rejected claims must not be evaluated again.
    5. Every service line's FROM_DT and TO_DT must belong
       to the same month and year.
    6. All service lines belonging to the same claim must also
       belong to the same month and year.
    7. Accepted claims remain unchanged.
    8. Invalid claims:
           CLCL_CUR_STS = '13'
           CDML_CUR_STS = '13'
           Insert into CW_RJCT_CLCL

    REJECT REASON
    ---------------------------------------------------------------
    Service Span dates are not in same month and year
*/

BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* ============================================================
       DECLARE LOCAL VARIABLES
       ============================================================ */

    DECLARE
        @run_id             INT =
        (
            SELECT ISNULL(MAX(RUN_ID), 0)
            FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)
        ),
        @job_id             VARCHAR(255) = 'CLCL_PROCESSING',
        @error              INT = 0,
        @step_id            INT = 0,
        @sys_def_msg        VARCHAR(5000),
        @sp_name            VARCHAR(255) = OBJECT_NAME(@@PROCID),
        @rows_processed     INT = 0,
        @step_desc          VARCHAR(255),
        @status_desc        VARCHAR(255),
        @status             VARCHAR(1);


    BEGIN TRANSACTION;

    BEGIN TRY

        SET @run_id = @run_id + 1;


        /* ========================================================
           STEP 1
           TAKE ELIGIBLE CLAIMS FOR SERVICE DATE VALIDATION
           ======================================================== */

        SET @step_id = @step_id + 1;

        SET @step_desc =
            'TAKE ELIGIBLE CLAIMS FOR SERVICE DATE VALIDATION';


        DROP TABLE IF EXISTS #SVC_DT_DATA;


        CREATE TABLE #SVC_DT_DATA
        (
            CLCL_ID             VARCHAR(10),
            CLCL_SUB_TYPE       VARCHAR(1),
            CLCL_TOT_CHG        MONEY,
            MEME_CK             INT,
            MEME_ID             INT,
            PRPR_ID             VARCHAR(20),
            CLCL_PA_ACCT_NO     VARCHAR(7),

            REJECT_STS          BIT DEFAULT 0,
            REJECT_REASON       VARCHAR(255)
        );


        /*
            Eligibility:

            Status 16        = submitted claim
            MEME_ID/CK       = Member Match completed
            PRPR_ID          = Provider Match completed
        */

        INSERT INTO #SVC_DT_DATA
        (
            CLCL_ID,
            CLCL_SUB_TYPE,
            CLCL_TOT_CHG,
            MEME_CK,
            MEME_ID,
            PRPR_ID,
            CLCL_PA_ACCT_NO
        )
        SELECT
            CLCL.CLCL_ID,
            CLCL.CLCL_SUB_TYPE,
            CLCL.CLCL_TOT_CHG,
            CLCL.MEME_CK,
            CLCL.MEME_ID,
            CLCL.PRPR_ID,
            CLCL.CLCL_PA_ACCT_NO

        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL

        WHERE CLCL.CLCL_CUR_STS = '16'

          /* Member Match Successful */
          AND CLCL.MEME_ID IS NOT NULL
          AND CLCL.MEME_CK IS NOT NULL

          /* Provider Match Successful */
          AND CLCL.PRPR_ID IS NOT NULL;


        SELECT
            @rows_processed = @@ROWCOUNT,
            @status_desc    = @step_desc + ' COMPLETED',
            @status         = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id          = @run_id,
             @job_id          = @job_id,
             @status_desc     = @status_desc,
             @sys_def_msg     = @sys_def_msg,
             @step_id         = @step_id,
             @sp_name         = @sp_name,
             @error           = @error,
             @rows_processed  = @rows_processed,
             @status          = @status;



        /* ========================================================
           STEP 2
           VALIDATE SERVICE DATES

           Validation:
           A. FROM_DT and TO_DT of every line must be in
              the same month/year.

           B. Every line belonging to a claim must use the
              same month/year as every other line.
           ======================================================== */

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'VALIDATE SERVICE DATES FOR SAME MONTH AND YEAR';


        ;WITH SERVICE_DATE_VALIDATION AS
        (
            SELECT
                D.CLCL_ID,

                /*
                    Number of distinct FROM date month/year
                    combinations for the claim.
                */
                COUNT
                (
                    DISTINCT
                    YEAR(D.CDML_FROM_DT) * 100
                    + MONTH(D.CDML_FROM_DT)
                ) AS FROM_MONTH_COUNT,

                /*
                    Number of distinct TO date month/year
                    combinations for the claim.
                */
                COUNT
                (
                    DISTINCT
                    YEAR(D.CDML_TO_DT) * 100
                    + MONTH(D.CDML_TO_DT)
                ) AS TO_MONTH_COUNT,

                /*
                    Detect a service line where FROM and TO
                    don't belong to the same month/year.
                */
                MAX
                (
                    CASE
                        WHEN D.CDML_FROM_DT IS NULL
                          OR D.CDML_TO_DT IS NULL
                            THEN 1

                        WHEN YEAR(D.CDML_FROM_DT)
                             <> YEAR(D.CDML_TO_DT)
                            THEN 1

                        WHEN MONTH(D.CDML_FROM_DT)
                             <> MONTH(D.CDML_TO_DT)
                            THEN 1

                        ELSE 0
                    END
                ) AS INVALID_LINE,

                /*
                    Get the earliest and latest month/year
                    appearing anywhere in the claim.
                */
                MIN
                (
                    YEAR(D.CDML_FROM_DT) * 100
                    + MONTH(D.CDML_FROM_DT)
                ) AS MIN_FROM_MONTH,

                MAX
                (
                    YEAR(D.CDML_TO_DT) * 100
                    + MONTH(D.CDML_TO_DT)
                ) AS MAX_TO_MONTH

            FROM FACETS_STG.dbo.STG_CMC_CDML D

            JOIN #SVC_DT_DATA S
                ON D.CLCL_ID = S.CLCL_ID

            GROUP BY
                D.CLCL_ID
        )

        UPDATE S
        SET
            S.REJECT_STS = 1,

            S.REJECT_REASON =
                'Service Span dates are not in same month and year'

        FROM #SVC_DT_DATA S

        JOIN SERVICE_DATE_VALIDATION V
            ON S.CLCL_ID = V.CLCL_ID

        WHERE
               V.INVALID_LINE = 1

            OR V.FROM_MONTH_COUNT > 1

            OR V.TO_MONTH_COUNT > 1

            OR V.MIN_FROM_MONTH <> V.MAX_TO_MONTH;


        SELECT
            @rows_processed = @@ROWCOUNT,
            @status_desc    = @step_desc + ' COMPLETED',
            @status         = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id          = @run_id,
             @job_id          = @job_id,
             @status_desc     = @status_desc,
             @sys_def_msg     = @sys_def_msg,
             @step_id         = @step_id,
             @sp_name         = @sp_name,
             @error           = @error,
             @rows_processed  = @rows_processed,
             @status          = @status;



        /* ========================================================
           STEP 3
           UPDATE REJECTED CLAIM HEADER STATUS TO 13
           ======================================================== */

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'UPDATE REJECTED CLAIM HEADER STATUS TO 13';


        UPDATE CLCL
        SET
            CLCL.CLCL_CUR_STS = '13'

        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL

        JOIN #SVC_DT_DATA S
            ON CLCL.CLCL_ID = S.CLCL_ID

        WHERE S.REJECT_STS = 1;


        SELECT
            @rows_processed = @@ROWCOUNT,
            @status_desc    = @step_desc + ' COMPLETED',
            @status         = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id          = @run_id,
             @job_id          = @job_id,
             @status_desc     = @status_desc,
             @sys_def_msg     = @sys_def_msg,
             @step_id         = @step_id,
             @sp_name         = @sp_name,
             @error           = @error,
             @rows_processed  = @rows_processed,
             @status          = @status;



        /* ========================================================
           STEP 4
           UPDATE ALL DETAIL LINES OF REJECTED CLAIM TO 13
           ======================================================== */

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'UPDATE REJECTED CLAIM DETAIL STATUS TO 13';


        UPDATE CDML
        SET
            CDML.CDML_CUR_STS = '13'

        FROM FACETS_STG.dbo.STG_CMC_CDML CDML

        JOIN #SVC_DT_DATA S
            ON CDML.CLCL_ID = S.CLCL_ID

        WHERE S.REJECT_STS = 1;


        SELECT
            @rows_processed = @@ROWCOUNT,
            @status_desc    = @step_desc + ' COMPLETED',
            @status         = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id          = @run_id,
             @job_id          = @job_id,
             @status_desc     = @status_desc,
             @sys_def_msg     = @sys_def_msg,
             @step_id         = @step_id,
             @sp_name         = @sp_name,
             @error           = @error,
             @rows_processed  = @rows_processed,
             @status          = @status;



        /* ========================================================
           STEP 5
           INSERT REJECTED CLAIM INTO CW_RJCT_CLCL
           ======================================================== */

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'INSERT SERVICE DATE REJECTED CLAIMS INTO REJECT TABLE';


        INSERT INTO dbo.CW_RJCT_CLCL
        (
            CLCL_ID,
            MEME_CK,
            CLCL_SUB_TYPE,
            CLCL_TOT_CHG,
            PRPR_ID,
            CLCL_PA_ACCT_NO,
            RJCT_REAS,
            UPDT_DTM
        )
        SELECT
            S.CLCL_ID,
            S.MEME_CK,
            S.CLCL_SUB_TYPE,
            S.CLCL_TOT_CHG,
            S.PRPR_ID,
            S.CLCL_PA_ACCT_NO,
            S.REJECT_REASON,
            GETDATE()

        FROM #SVC_DT_DATA S

        WHERE S.REJECT_STS = 1

          /*
             Extra protection against duplicate rejection rows
             if the procedure is rerun.
          */
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.CW_RJCT_CLCL R
              WHERE R.CLCL_ID = S.CLCL_ID
                AND R.RJCT_REAS =
                    'Service Span dates are not in same month and year'
          );


        SELECT
            @rows_processed = @@ROWCOUNT,
            @status_desc    = @step_desc + ' COMPLETED',
            @status         = 'C';


        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id          = @run_id,
             @job_id          = @job_id,
             @status_desc     = @status_desc,
             @sys_def_msg     = @sys_def_msg,
             @step_id         = @step_id,
             @sp_name         = @sp_name,
             @error           = @error,
             @rows_processed  = @rows_processed,
             @status          = @status;


        COMMIT TRANSACTION;

    END TRY


    BEGIN CATCH

        SELECT
            @error       = ERROR_NUMBER(),
            @sys_def_msg = ERROR_MESSAGE(),
            @status_desc = ISNULL(@step_desc, 'CLAIM SERVICE DATE VALIDATION')
                           + ' Failed.',
            @status      = 'E';


        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;


        /*
            Log technical error after rollback so the error
            record isn't rolled back with the business transaction.
        */

        EXEC dbo.USP_CLM_STEP_ERR_LOG
             @run_id          = @run_id,
             @job_id          = @job_id,
             @status_desc     = @status_desc,
             @sys_def_msg     = @sys_def_msg,
             @step_id         = @step_id,
             @sp_name         = @sp_name,
             @error           = @error,
             @rows_processed  = @rows_processed,
             @status          = @status;


        THROW;

    END CATCH;

END
GO


-- Execute the Procedure
EXEC [dbo].[USP_CLM_SVCDT_VAL]

--- Check the tables
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CDML]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CLCL]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CLPR]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_MEME]
SELECT * FROM FACETS_Custom.[dbo].[CW_RJCT_CLCL]
