USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_PRVDR_MTCH]
AS

/*  
    CREATED BY      - Nawaraj Adhikari
    CREATION DATE   - 08/30/2026
    DESCRIPTION     - PERFORM PROVIDER SELECTION / PROVIDER MATCH
                      FOR SUBMITTED CLAIMS

    PROVIDER SELECTION RULE:
        1. Process submitted claims with status 16
           and successful Member Match.
        2. Evaluate Billing Provider (85) first.
        3. If 85 has a single NPI match, use that provider.
        4. If 85 does not have a single match, evaluate
           Servicing Provider (77).
        5. If 77 has a single NPI match, use that provider.
        6. If neither produces a single match, reject claim.
        7. Update PRPR_ID in STG_CMC_CLCL and STG_CMC_CDML.
        8. Rejected provider claims receive status 12.
*/

BEGIN

    /* DECLARE LOCAL VARIABLES */
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


        /**************************************************************
          STEP 1
          TAKE ALL ELIGIBLE CLAIMS INTO TEMP TABLE
        **************************************************************/

        SET @step_id = @step_id + 1;
        SET @step_desc =
            'TAKE ALL ELIGIBLE CLAIMS FOR PROVIDER SELECTION INTO TEMP TABLE';


        DROP TABLE IF EXISTS #PRVDR_DATA;


        CREATE TABLE #PRVDR_DATA
        (
            CLCL_ID             VARCHAR(10),
            PRPR_ID             VARCHAR(20),
            MATCH_STS           BIT DEFAULT 0,
            MATCH_PROVIDER_TYPE VARCHAR(2),

            CLCL_SUB_TYPE       VARCHAR(1),
            CLCL_TOT_CHG        MONEY,
            MEME_CK             INT,
            MEME_ID             INT,
            CLCL_PA_ACCT_NO     VARCHAR(7)
        );


        INSERT INTO #PRVDR_DATA
        (
            CLCL_ID,
            MATCH_STS,
            CLCL_SUB_TYPE,
            CLCL_TOT_CHG,
            MEME_CK,
            MEME_ID,
            CLCL_PA_ACCT_NO
        )
        SELECT
            CLCL.CLCL_ID,
            0,
            CLCL.CLCL_SUB_TYPE,
            CLCL.CLCL_TOT_CHG,
            CLCL.MEME_CK,
            CLCL.MEME_ID,
            CLCL.CLCL_PA_ACCT_NO
        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL
        WHERE CLCL.CLCL_CUR_STS = '16'
          AND CLCL.MEME_ID IS NOT NULL
          AND CLCL.MEME_CK IS NOT NULL
          AND CLCL.PRPR_ID IS NULL;


        /* Step Logging */
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



        /**************************************************************
          STEP 2
          MATCH BILLING PROVIDER - TYPE 85

          Business rule:
          Evaluate provider type 85 first.

          Only a SINGLE NPI match is considered successful.
        **************************************************************/

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'VALIDATE BILLING PROVIDER TYPE 85 NPI WITH PROVIDER MASTER';


        ;WITH PROVIDER_85_MATCH AS
        (
            SELECT
                P.CLCL_ID,
                MAX(PRPR.PRPR_ID) AS PRPR_ID,
                COUNT(*) AS MATCH_COUNT
            FROM #PRVDR_DATA P

            JOIN FACETS_STG.dbo.STG_CMC_CLPR CLPR
                ON P.CLCL_ID = CLPR.CLCL_ID
               AND CLPR.CLPR_TYPE = '85'

            JOIN FACETS.dbo.CMC_PRPR PRPR
                ON CLPR.CLPR_NPI = PRPR.PRPR_NPI

            WHERE P.MATCH_STS = 0

            GROUP BY
                P.CLCL_ID
        )

        UPDATE P
        SET
            P.PRPR_ID             = M.PRPR_ID,
            P.MATCH_STS           = 1,
            P.MATCH_PROVIDER_TYPE = '85'
        FROM #PRVDR_DATA P

        JOIN PROVIDER_85_MATCH M
            ON P.CLCL_ID = M.CLCL_ID

        WHERE M.MATCH_COUNT = 1;


        /* Step Logging */
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



        /**************************************************************
          STEP 3
          IF TYPE 85 DID NOT MATCH,
          TRY SERVICING PROVIDER TYPE 77
        **************************************************************/

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'VALIDATE SERVICING PROVIDER TYPE 77 NPI WITH PROVIDER MASTER';


        ;WITH PROVIDER_77_MATCH AS
        (
            SELECT
                P.CLCL_ID,
                MAX(PRPR.PRPR_ID) AS PRPR_ID,
                COUNT(*) AS MATCH_COUNT
            FROM #PRVDR_DATA P

            JOIN FACETS_STG.dbo.STG_CMC_CLPR CLPR
                ON P.CLCL_ID = CLPR.CLCL_ID
               AND CLPR.CLPR_TYPE = '77'

            JOIN FACETS.dbo.CMC_PRPR PRPR
                ON CLPR.CLPR_NPI = PRPR.PRPR_NPI

            WHERE P.MATCH_STS = 0

            GROUP BY
                P.CLCL_ID
        )

        UPDATE P
        SET
            P.PRPR_ID             = M.PRPR_ID,
            P.MATCH_STS           = 1,
            P.MATCH_PROVIDER_TYPE = '77'
        FROM #PRVDR_DATA P

        JOIN PROVIDER_77_MATCH M
            ON P.CLCL_ID = M.CLCL_ID

        WHERE M.MATCH_COUNT = 1;


        /* Step Logging */
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



        /**************************************************************
          STEP 4
          UPDATE CLAIM HEADER

          Successful match:
              Update PRPR_ID

          No match:
              Set claim status = 12
        **************************************************************/

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'UPDATE CLAIM HEADER WITH PROVIDER MATCH INFORMATION';


        UPDATE CLCL
        SET
            CLCL.PRPR_ID =
                CASE
                    WHEN P.MATCH_STS = 1
                    THEN P.PRPR_ID
                    ELSE CLCL.PRPR_ID
                END,

            CLCL.CLCL_CUR_STS =
                CASE
                    WHEN P.MATCH_STS = 0
                    THEN '12'
                    ELSE CLCL.CLCL_CUR_STS
                END

        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL

        JOIN #PRVDR_DATA P
            ON CLCL.CLCL_ID = P.CLCL_ID;


        /* Step Logging */
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



        /**************************************************************
          STEP 5
          UPDATE CLAIM DETAIL

          Successful:
              Update PRPR_ID

          Rejected:
              Update CDML_CUR_STS = 12
        **************************************************************/

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'UPDATE CLAIM DETAIL WITH PROVIDER MATCH INFORMATION';


        UPDATE CDML
        SET
            CDML.PRPR_ID =
                CASE
                    WHEN P.MATCH_STS = 1
                    THEN P.PRPR_ID
                    ELSE CDML.PRPR_ID
                END,

            CDML.CDML_CUR_STS =
                CASE
                    WHEN P.MATCH_STS = 0
                    THEN '12'
                    ELSE CDML.CDML_CUR_STS
                END

        FROM FACETS_STG.dbo.STG_CMC_CDML CDML

        JOIN #PRVDR_DATA P
            ON CDML.CLCL_ID = P.CLCL_ID;


        /* Step Logging */
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



        /**************************************************************
          STEP 6
          INSERT PROVIDER REJECTED CLAIMS
        **************************************************************/

        SET @rows_processed = 0;
        SET @step_id = @step_id + 1;

        SET @step_desc =
            'INSERT PROVIDER NOT FOUND CLAIMS INTO REJECT TABLE';


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
            P.CLCL_ID,
            P.MEME_CK,
            P.CLCL_SUB_TYPE,
            P.CLCL_TOT_CHG,
            P.PRPR_ID,
            P.CLCL_PA_ACCT_NO,

            'INVALID PROVIDER DETAILS SUBMITTED ON CLAIM',

            GETDATE()

        FROM #PRVDR_DATA P

        WHERE P.MATCH_STS = 0;


        /* Step Logging */
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
            @error           = ERROR_NUMBER(),
            @sys_def_msg     = ERROR_MESSAGE(),
            @status_desc     = @step_desc + ' Failed.',
            @status          = 'E';


        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;


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

-- Execute the Proc
EXEC [dbo].[USP_CLM_PRVDR_MTCH]

--- Check the table
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CDML]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CLCL]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CLPR]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_MEME]
SELECT * FROM FACETS_Custom.[dbo].[CW_RJCT_CLCL]



--- Let's check by adding new data
DECLARE @LINE_DATA STG_CMC_CDML_TYPE
DECLARE @CLPR_DATA STG_CMC_CLPR_TYPE;
-- Insert sample data into the table variable
INSERT INTO @LINE_DATA (CDML_CHG_AMT, CDML_FROM_DT, CDML_TO_DT, DIAG_CD, PROC_CD)
VALUES (964.33, '2026-01-12', '2026-01-18', 'D01','H6245'),
  (785.00, '2026-02-22', '2026-02-28', 'H551','HPC0001');
-- Insert sample data into the table variable
INSERT INTO @CLPR_DATA (CLPR_TYPE,CLPR_TAX,CLPR_NPI,CLPR_STATE)
VALUES ('77', 'CA08254103','139397894', 'CA'),
 ('85', 'CA08254103','0056337894', 'CA')
-- Execute the stored procedure     
EXEC [dbo].[USP_CLM_LOAD_STG_DATA] 'M','I','5877456','Dennis','Parker','R','1956-04-01', @LINE_DATA = @LINE_DATA, @CLPR_DATA = @CLPR_DATA
GO
DECLARE @LINE_DATA STG_CMC_CDML_TYPE
DECLARE @CLPR_DATA STG_CMC_CLPR_TYPE;
-- Insert sample data into the table variable
INSERT INTO @LINE_DATA (CDML_CHG_AMT, CDML_FROM_DT, CDML_TO_DT, DIAG_CD, PROC_CD)
VALUES (964.33, '2026-01-12', '2026-01-18', 'D01','H6245'),
  (785.00, '2026-02-22', '2026-02-28', 'H551','HPC0001');
-- Insert sample data into the table variable
INSERT INTO @CLPR_DATA (CLPR_TYPE,CLPR_TAX,CLPR_NPI,CLPR_STATE)
VALUES ('77', 'CA08254103','139397894', 'CA'),
 ('85', 'WA08266ADB','754372876', 'CA')
-- Execute the stored procedure     
EXEC [dbo].[USP_CLM_LOAD_STG_DATA] 'M','I','5877456','Christina','Hernandez','B','1971-09-02', @LINE_DATA = @LINE_DATA, @CLPR_DATA = @CLPR_DATA
GO
DECLARE @LINE_DATA STG_CMC_CDML_TYPE
DECLARE @CLPR_DATA STG_CMC_CLPR_TYPE;
-- Insert sample data into the table variable
INSERT INTO @LINE_DATA (CDML_CHG_AMT, CDML_FROM_DT, CDML_TO_DT, DIAG_CD, PROC_CD)
VALUES (964.33, '2026-01-12', '2026-01-18', 'D01','H6245'),
  (785.00, '2026-02-22', '2026-02-28', 'H551','HPC0001');
-- Insert sample data into the table variable
INSERT INTO @CLPR_DATA (CLPR_TYPE,CLPR_TAX,CLPR_NPI,CLPR_STATE)
VALUES ('77', 'CA08254103','13000894', 'CA'),
 ('85', 'WA08266ADB','75000876', 'CA')
-- Execute the stored procedure     
EXEC [dbo].[USP_CLM_LOAD_STG_DATA] 'M','I','5877456','Juan','Dunn','C','1986-09-10', @LINE_DATA = @LINE_DATA, @CLPR_DATA = @CLPR_DATA
GO