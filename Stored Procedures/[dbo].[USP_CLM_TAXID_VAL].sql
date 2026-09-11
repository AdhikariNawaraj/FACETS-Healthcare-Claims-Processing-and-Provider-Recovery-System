
USE [FACETS_Custom]
GO

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

CREATE OR ALTER PROCEDURE [dbo].[USP_CLM_TAXID_VAL]
AS

/* EXEC dbo.USP_CLM_TAXID_VAL */

BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* =========================================================
       DECLARE LOCAL VARIABLES
       ========================================================= */

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


    BEGIN TRANSACTION;

    BEGIN TRY

        SET @RUN_ID = @RUN_ID + 1;


        /* =====================================================
           STEP 1
           IDENTIFY CLAIMS WITH INVALID PROVIDER TAX ID
           ===================================================== */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'IDENTIFY CLAIMS FAILED PROVIDER TAX ID VALIDATION';


        DROP TABLE IF EXISTS #InvalidClaims;


        SELECT DISTINCT

            CLCL.CLCL_ID,
            CLCL.PRPR_ID,

            PRPR.PRPR_NPI,

            CLPR.CLPR_TYPE,
            CLPR.CLPR_TAX,

            PRPR.MCTN_ID,

            CLCL.MEME_CK,
            CLCL.CLCL_SUB_TYPE,
            CLCL.CLCL_TOT_CHG,
            CLCL.CLCL_PA_ACCT_NO

        INTO #InvalidClaims

        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL


        /* Selected Provider */

        INNER JOIN FACETS.dbo.CMC_PRPR PRPR

            ON CLCL.PRPR_ID = PRPR.PRPR_ID


        /* Find submitted provider record for selected provider */

        INNER JOIN FACETS_STG.dbo.STG_CMC_CLPR CLPR

            ON CLPR.CLCL_ID = CLCL.CLCL_ID

           AND CLPR.CLPR_NPI = PRPR.PRPR_NPI

           AND CLPR.CLPR_TYPE IN ('85','77')


        WHERE

            /* Claim must still be eligible */

            CLCL.CLCL_CUR_STS = '16'


            /* Member Match must be completed */

            AND CLCL.MEME_ID IS NOT NULL


            /* Provider Match must be completed */

            AND CLCL.PRPR_ID IS NOT NULL


            /* Tax ID Validation */

            AND
            (
                   CLPR.CLPR_TAX IS NULL

                OR LTRIM(RTRIM(CLPR.CLPR_TAX)) = ''

                OR PRPR.MCTN_ID IS NULL

                OR LTRIM(RTRIM(PRPR.MCTN_ID)) = ''

                OR LTRIM(RTRIM(CLPR.CLPR_TAX))
                   <>
                   LTRIM(RTRIM(PRPR.MCTN_ID))
            );


        SELECT
            @ROWS_PROCESSED = @@ROWCOUNT,
            @STATUS_DESC =
                @STEP_DESC + ' COMPLETED',
            @STATUS = 'C';


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



        /* =====================================================
           STEP 2
           UPDATE CLAIM HEADER STATUS
           ===================================================== */

        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'UPDATE CLAIM HEADER STATUS FOR INVALID PROVIDER TAX ID';


        UPDATE CLCL

        SET CLCL.CLCL_CUR_STS = '14'

        FROM FACETS_STG.dbo.STG_CMC_CLCL CLCL

        INNER JOIN #InvalidClaims IC
            ON CLCL.CLCL_ID = IC.CLCL_ID;


        SELECT
            @ROWS_PROCESSED = @@ROWCOUNT,
            @STATUS_DESC =
                @STEP_DESC + ' COMPLETED',
            @STATUS = 'C';


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



        /* =====================================================
           STEP 3
           UPDATE CLAIM DETAIL STATUS
           ===================================================== */

        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'UPDATE CLAIM DETAIL STATUS FOR INVALID PROVIDER TAX ID';


        UPDATE CDML

        SET CDML.CDML_CUR_STS = '14'

        FROM FACETS_STG.dbo.STG_CMC_CDML CDML

        INNER JOIN #InvalidClaims IC
            ON CDML.CLCL_ID = IC.CLCL_ID;


        SELECT
            @ROWS_PROCESSED = @@ROWCOUNT,
            @STATUS_DESC =
                @STEP_DESC + ' COMPLETED',
            @STATUS = 'C';


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



        /* =====================================================
           STEP 4
           INSERT REJECTED CLAIM
           ===================================================== */

        SET @ROWS_PROCESSED = 0;
        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'INSERT TAX ID REJECTED CLAIMS INTO REJECT TABLE';


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

        SELECT DISTINCT

            IC.CLCL_ID,
            IC.MEME_CK,
            IC.CLCL_SUB_TYPE,
            IC.CLCL_TOT_CHG,
            IC.PRPR_ID,
            IC.CLCL_PA_ACCT_NO,

            'Provider Tax ID is incorrect for submitted Claim',

            GETDATE()

        FROM #InvalidClaims IC

        WHERE NOT EXISTS
        (
            SELECT 1

            FROM dbo.CW_RJCT_CLCL R

            WHERE R.CLCL_ID = IC.CLCL_ID

              AND R.RJCT_REAS =
                  'Provider Tax ID is incorrect for submitted Claim'
        );


        SELECT
            @ROWS_PROCESSED = @@ROWCOUNT,
            @STATUS_DESC =
                @STEP_DESC + ' COMPLETED',
            @STATUS = 'C';


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


    END TRY

    BEGIN CATCH

        SELECT
            @ERROR =
                ERROR_NUMBER(),

            @SYS_DEF_MSG =
                ERROR_MESSAGE(),

            @STATUS_DESC =
                ISNULL(@STEP_DESC, 'PROVIDER TAX ID VALIDATION')
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
EXEC [dbo].[USP_CLM_TAXID_VAL]

--- Check the tables
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CDML]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CLCL]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_CLPR]
SELECT * FROM FACETS_STG.[dbo].[STG_CMC_MEME]
SELECT * FROM FACETS_Custom.[dbo].[CW_RJCT_CLCL]