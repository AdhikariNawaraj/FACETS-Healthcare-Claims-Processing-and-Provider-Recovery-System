USE [FACETS_Custom]
GO

CREATE OR ALTER PROCEDURE dbo.USP_CLM_PYMT_RECOV
(
    @CLCL_ID   VARCHAR(10),
    @PRPR_ID   VARCHAR(10),
    @RECOV_AMT MONEY
)
AS
/*
=====================================================================
 PROCEDURE : USP_CLM_PYMT_RECOV
 PURPOSE   : Process partial/full provider recovery payments.

 INPUT
 --------------------------------------------------------------------
 @CLCL_ID   = Claim ID
 @PRPR_ID   = Provider ID
 @RECOV_AMT = Current recovery payment

 BUSINESS RULES
 --------------------------------------------------------------------
 1. Provider may make partial payments.
 2. Locate the ACPR record associated with Claim + Provider.
 3. Add current payment to ACPR_RECOV_AMT.
 4. Reduce ACPR_NET_AMT by current payment.
 5. When ACPR_NET_AMT becomes zero, set ACPR_STS = 'I'.
 6. Insert recovery transaction into CMC_ACRH.
 7. Recovery cannot exceed remaining ACPR_NET_AMT.
=====================================================================
*/
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* =============================================================
       DECLARE VARIABLES
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
        @STATUS             VARCHAR(1),

        /* Recovery variables */

        @ACPR_REF_ID        VARCHAR(10),
        @ACPR_TYPE          VARCHAR(2),
        @ACPR_SUB_TYPE      VARCHAR(1),
        @ACPR_ORIG_AMT      MONEY,
        @ACPR_NET_AMT       MONEY,
        @ACPR_RECOV_AMT     MONEY,
        @NEW_NET_AMT        MONEY,
        @NEW_RECOV_AMT      MONEY;


    SET @RUN_ID = @RUN_ID + 1;


    /* =============================================================
       INPUT VALIDATION
       ============================================================= */

    IF @CLCL_ID IS NULL
       OR LTRIM(RTRIM(@CLCL_ID)) = ''
    BEGIN
        THROW 50001, 'CLCL_ID cannot be NULL or empty.', 1;
    END;


    IF @PRPR_ID IS NULL
       OR LTRIM(RTRIM(@PRPR_ID)) = ''
    BEGIN
        THROW 50002, 'PRPR_ID cannot be NULL or empty.', 1;
    END;


    IF @RECOV_AMT IS NULL OR @RECOV_AMT <= 0
    BEGIN
        THROW 50003, 'Recovery amount must be greater than zero.', 1;
    END;


    BEGIN TRANSACTION;

    BEGIN TRY

        /* =========================================================
           STEP 1
           FIND ACPR RECORD ASSOCIATED WITH CLAIM AND PROVIDER

           CMC_CLOV connects:
                CLCL_ID → ACPR_REF_ID

           CMC_ACPR contains:
                ACPR_REF_ID → Provider/payment information
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'IDENTIFY ACPR RECORD FOR PROVIDER RECOVERY';


        SELECT
            @ACPR_REF_ID    = ACPR.ACPR_REF_ID,
            @ACPR_TYPE      = ACPR.ACPR_TYPE,
            @ACPR_SUB_TYPE  = ACPR.ACPR_SUB_TYPE,
            @ACPR_ORIG_AMT  = ACPR.ACPR_ORIG_AMT,
            @ACPR_NET_AMT   = ACPR.ACPR_NET_AMT,
            @ACPR_RECOV_AMT = ISNULL(ACPR.ACPR_RECOV_AMT,0)

        FROM FACETS.dbo.CMC_CLOV CLOV

        INNER JOIN FACETS.dbo.CMC_ACPR ACPR
            ON CLOV.ACPR_REF_ID = ACPR.ACPR_REF_ID

        WHERE CLOV.CLCL_ID = @CLCL_ID
          AND ACPR.ACPR_PAYEE_ID = @PRPR_ID
          AND ACPR.ACPR_STS = 'A';


        IF @ACPR_REF_ID IS NULL
        BEGIN
            THROW 50004,
            'No active ACPR recovery record found for the Claim and Provider.',
            1;
        END;


        SET @ROWS_PROCESSED = 1;
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
           STEP 2
           VALIDATE RECOVERY AMOUNT

           Provider cannot pay more than remaining balance.
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'VALIDATE PROVIDER RECOVERY AMOUNT';


        IF ISNULL(@ACPR_NET_AMT,0) <= 0
        BEGIN
            THROW 50005,
            'ACPR recovery balance is already zero.',
            1;
        END;


        IF @RECOV_AMT > @ACPR_NET_AMT
        BEGIN
            THROW 50006,
            'Recovery amount cannot exceed remaining ACPR NET amount.',
            1;
        END;


        /*
            Example:

            Existing:
              ORIG  = 1000
              RECOV = 200
              NET   = 800

            Current payment:
              300

            Result:
              RECOV = 200 + 300 = 500
              NET   = 800 - 300 = 500
        */

        SET @NEW_RECOV_AMT =
            ISNULL(@ACPR_RECOV_AMT,0) + @RECOV_AMT;

        SET @NEW_NET_AMT =
            ISNULL(@ACPR_NET_AMT,0) - @RECOV_AMT;


        SET @ROWS_PROCESSED = 1;
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
           STEP 3
           UPDATE ACPR RECOVERY INFORMATION
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'UPDATE ACPR PROVIDER RECOVERY AMOUNTS';


        UPDATE FACETS.dbo.CMC_ACPR

        SET
            ACPR_RECOV_AMT = @NEW_RECOV_AMT,

            ACPR_NET_AMT = @NEW_NET_AMT,

            ACPR_STS =
                CASE
                    WHEN @NEW_NET_AMT = 0
                        THEN 'I'
                    ELSE 'A'
                END

        WHERE ACPR_REF_ID   = @ACPR_REF_ID
          AND ACPR_TYPE     = @ACPR_TYPE
          AND ACPR_SUB_TYPE = @ACPR_SUB_TYPE;


        SET @ROWS_PROCESSED = @@ROWCOUNT;
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
           STEP 4
           INSERT RECOVERY HISTORY INTO CMC_ACRH

           CMC_ACRH:
             ACPR_REF_ID
             ACPR_TYPE
             ACPR_SUB_TYPE
             ACRH_CREATE_DT
             ACRH_EVENT_TYPE
             ACRH_AMT
             ACRH_MCTR_RSN
           ========================================================= */

        SET @STEP_ID = @STEP_ID + 1;

        SET @STEP_DESC =
            'INSERT PROVIDER RECOVERY HISTORY INTO CMC_ACRH';


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
        VALUES
        (
            @ACPR_REF_ID,
            @ACPR_TYPE,
            @ACPR_SUB_TYPE,
            GETDATE(),

            /* R = Recovery */
            'R',

            @RECOV_AMT,

            /* Provider Recovery */
            'RECOVERY'
        );


        SET @ROWS_PROCESSED = @@ROWCOUNT;
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


        COMMIT TRANSACTION;


        /* =========================================================
           RETURN RECOVERY RESULT
           ========================================================= */

        SELECT
            @CLCL_ID AS CLCL_ID,
            @PRPR_ID AS PRPR_ID,
            @ACPR_REF_ID AS ACPR_REF_ID,
            @ACPR_ORIG_AMT AS ACPR_ORIG_AMT,
            @RECOV_AMT AS CURRENT_RECOVERY_AMT,
            @NEW_RECOV_AMT AS TOTAL_RECOVERED_AMT,
            @NEW_NET_AMT AS REMAINING_NET_AMT,

            CASE
                WHEN @NEW_NET_AMT = 0
                    THEN 'I'
                ELSE 'A'
            END AS ACPR_STATUS;


    END TRY

    BEGIN CATCH

        SELECT
            @ERROR = ERROR_NUMBER(),
            @SYS_DEF_MSG = ERROR_MESSAGE(),
            @STATUS_DESC =
                ISNULL(@STEP_DESC,'PROVIDER RECOVERY PROCESS')
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


EXEC dbo.USP_CLM_PYMT_RECOV
    @CLCL_ID = '2500000022',
    @PRPR_ID = 'PR10001',
    @RECOV_AMT = 300