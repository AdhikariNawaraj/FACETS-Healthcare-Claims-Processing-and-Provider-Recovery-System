USE [FACETS_Custom]
GO

/****** Object:  StoredProcedure [dbo].[USP_CLM_LOAD_STG_DATA]    Script Date: 27-08-2026 06:33:26 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- DROP PROC [dbo].[USP_CLM_LOAD_STG_DATA]

CREATE OR ALTER   PROCEDURE [dbo].[USP_CLM_LOAD_STG_DATA]
(
	@CLCL_SUB_TYPE		VARCHAR(1),
	@CLCL_NTWK_IND		VARCHAR(1),
	@CLCL_PA_ACCT_NO	VARCHAR(7),
	@MEME_FIRST_NAME	VARCHAR(50),
	@MEME_LAST_NAME		VARCHAR(50),
	@MID_INIT			VARCHAR(30),
	@BIRTH_DT			DATE,
	@LINE_DATA			dbo.STG_CMC_CDML_TYPE READONLY,
	@CLPR_DATA			dbo.STG_CMC_CLPR_TYPE READONLY
)
AS

/*	CREATED BY		- SHIVRAJ WANKAR
	CREATION DATE	- 08/27/2026
	DESCRIPTION		- STORED PROCEDURE TO LOAD THE DATA INTO STG TABLE (FACETS STG DATABASE)
	TABLES USED		-
	MODIFIED DATE	- 
	REVISON HISTORY
	REV NO		AUTHOR	DATE	DESC

	SAMPLE EXECUTION CALL:
 -- Declare a variable of the table type
DECLARE @LINE_DATA STG_CMC_CDML_TYPE
DECLARE @CLPR_DATA STG_CMC_CLPR_TYPE;

 -- Insert sample data into the table variable
INSERT INTO @LINE_DATA (CDML_CHG_AMT, CDML_FROM_DT, CDML_TO_DT, DIAG_CD, PROC_CD)
VALUES (100.00, '2025-01-01', '2025-01-12', 'D01','HPC0001'),
       (200.00, '2025-01-02', '2025-01-15', 'D02','HPC0001');

 -- Insert sample data into the table variable
INSERT INTO @CLPR_DATA (CLPR_TYPE,CLPR_TAX,CLPR_NPI,CLPR_STATE)
VALUES ('85', 'TAX10212','NPI00102', 'NY'),
       ('77', 'TAX1WQ2', 'NPI0HGT2', 'WA');

 -- Execute the stored procedure
EXEC [dbo].[USP_CLM_LOAD_STG_DATA] 'M','I','63223452','Henry','Collins',NULL,'1974-11-12', @LINE_DATA = @LINE_DATA, @CLPR_DATA = @CLPR_DATA;
*/

BEGIN

	/*  DECLARE LOCAL VARIABLES */
	DECLARE 
	@run_id				INT				= (SELECT ISNULL(MAX(RUN_ID),0) FROM dbo.CLM_JOB_STEP_LOG WITH(NOLOCK)),
	@job_id				VARCHAR(255)	= 'CLCL_PROCESSING',
	@errro_msg			VARCHAR(255),
	@err_dtm			DATETIME,
	@error				INT				= 0,
	@step_id			INT				= 0,
	@user_def_msg		VARCHAR(5000),
	@sys_def_msg		VARCHAR(5000),
	@sp_start_dtm		DATETIME		= GETDATE(),	
	@sp_name			VARCHAR(255)	= (SELECT OBJECT_NAME(@@PROCID)),
	@rows_processed		INT				= 0,
	@step_desc			VARCHAR(255),
	@status_desc		VARCHAR(255),
	@status				VARCHAR(1),
	@empty_string		VARCHAR(1)		= '',
	@completion_status	VARCHAR(255)	= 'C',
	@SequenceValue		INT

	BEGIN TRANSACTION;
	BEGIN TRY
		
		SET @run_id = @run_id + 1  

		-- GENERATE CLAIM NUMBER --

		SET @STEP_ID = @STEP_ID + 1
		SET @STATUS_DESC = 'GENEREATE UNIQUE CLAIM NUMBER USING SEQUENCE'

		DECLARE @CLCL_ID VARCHAR(12)
		DECLARE @Seq INT = NEXT VALUE FOR [dbo].[CLCL_ID_1031SEQ]
		DECLARE @VarSeq VARCHAR(7) = RIGHT('0000000' + CAST(@Seq AS VARCHAR(7)),7)	

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'	
			   
		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status	

		SET @step_id	= @step_id + 1 
		SET @step_desc	= 'INSERT CLAIM DATA INTO STG_CMC_CLCL TABLE RECEIVED FROM PROVIDER'
		/* INSERT CLAIM DATA INTO STG_CMC_CLCL TABLE RECEIVED FROM PROVIDER */

		INSERT INTO FACETS_STG.dbo.STG_CMC_CLCL
		(
			CLCL_ID,
			CLCL_SUB_TYPE,
			CLCL_CUR_STS,
			CLCL_NTWK_IND,
			CLCL_PA_ACCT_NO,
			CLCL_INPUT_DT
		)
		VALUES
		(
			@CLCL_ID,
			@CLCL_SUB_TYPE,
			'16',					-- DEFAULT CLAIM STATUS FOR SUBMITTED CLAIM
			@CLCL_NTWK_IND,
			@CLCL_PA_ACCT_NO,
			GETDATE()
		)

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'	
			   
		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status									  
		
		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'INSERT LINE LEVEL CLAIM DATA INTO STG_CMC_CDML TABLE RECEIVED FROM PROVIDER'
		/* INSERT LINE LEVEL CLAIM DATA INTO STG_CMC_CDML TABLE RECEIVED FROM PROVIDER */

		DECLARE @CDML_SEQ		SMALLINT = 0,
				@CDML_CHG_AMT	MONEY,
				@CDML_FROM_DT	DATE,
				@CDML_TO_DT		DATE,
				@DIAG_CD		VARCHAR(7),
				@PROC_CD		VARCHAR(7)

		-- Insert line-level data into CMC_CDML table with sequential CDML_SEQ
		DECLARE CDML_Cursor CURSOR FOR
		SELECT 
			CDML_CHG_AMT,
			CDML_FROM_DT,
			CDML_TO_DT	,
			DIAG_CD		,
			PROC_CD		
		FROM @LINE_DATA;
		
		OPEN CDML_Cursor;
		FETCH NEXT FROM CDML_Cursor INTO @CDML_CHG_AMT, @CDML_FROM_DT, @CDML_TO_DT, @DIAG_CD, @PROC_CD;
		
		WHILE @@FETCH_STATUS = 0
		BEGIN
		    -- Increment the CDML_SEQ for each detail
		    SET @CDML_SEQ = @CDML_SEQ + 1;
		
		    -- Insert into CMC_CDML
		    INSERT INTO FACETS_STG.dbo.STG_CMC_CDML
			(
				CLCL_ID,
				CDML_SEQ,
				CDML_SUB_TYPE,
				CDML_CHG_AMT,
				CDML_CUR_STS,
				CDML_FROM_DT,
				CDML_TO_DT,
				DIAG_CD,
				PROC_CD,
				CDML_NTWK_IND,
				CDML_INPUT_DT
			)
		    SELECT 
				@CLCL_ID,
				@CDML_SEQ,
				@CLCL_SUB_TYPE,
				@CDML_CHG_AMT,
				'16',
				@CDML_FROM_DT,
				@CDML_TO_DT,
				@DIAG_CD,
				@PROC_CD,
				@CLCL_NTWK_IND,
				GETDATE()
		    
		    FETCH NEXT FROM CDML_Cursor INTO @CDML_CHG_AMT, @CDML_FROM_DT, @CDML_TO_DT, @DIAG_CD, @PROC_CD;
		END
		
		CLOSE CDML_Cursor;
		DEALLOCATE CDML_Cursor;
		
		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'	
			   
		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'INSERT PROVIDER DETAILS FOR THE CLAIM INTO STG_CMC_CLPR TABLE RECEIVED FROM PROVIDER'
		/* INSERT PROVIDER DETAILS FOR THE CLAIM INTO STG_CMC_CLPR TABLE RECEIVED FROM PROVIDER */

		INSERT INTO FACETS_STG.dbo.STG_CMC_CLPR
			(
				CLCL_ID
			   ,CLPR_TYPE
			   ,CLPR_TAX
			   ,CLPR_NPI
			   ,CLPR_STATE
			   ,CLPR_DT
			)
			SELECT
				@CLCL_ID
			   ,CLPR_TYPE
			   ,CLPR_TAX
			   ,CLPR_NPI
			   ,CLPR_STATE
			   ,GETDATE()
			FROM @CLPR_DATA

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'	
			   
		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'INSERT MEMBER DETAILS FOR THE CLAIM INTO STG_CMC_MEME TABLE RECEIVED FROM PROVIDER'
		/* INSERT MEMBER DETAILS FOR THE CLAIM INTO STG_CMC_MEME TABLE RECEIVED FROM PROVIDER */

		INSERT INTO FACETS_STG.dbo.STG_CMC_MEME
		(
			CLCL_ID,
			MEME_FIRST_NAME,
			MID_INIT,
			MEME_LAST_NAME,
			BIRTH_DT
		)
		VALUES
		(
			@CLCL_ID,
			@MEME_FIRST_NAME,
			@MID_INIT,
			@MEME_LAST_NAME,
			@BIRTH_DT
		)

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'	
			   
		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		SET @rows_processed	= 0
		SET @step_id		= @step_id + 1
		SET @step_desc		= 'UPDATE CLAIM TABLE WITH TOTAL CHARGE AND SERVICE DATES FROM LINE LEVEL DATA'
		/* UPDATE CLAIM TABLE WITH TOTAL CHARGE AND SERVICE DATES FROM LINE LEVEL DATA */

		DECLARE @LOW_SVC_DT DATETIME
		SET @LOW_SVC_DT = (SELECT MIN(CDML_FROM_DT) FROM FACETS_STG.dbo.STG_CMC_CDML WHERE CLCL_ID = @CLCL_ID GROUP BY CLCL_ID)

		DECLARE @HIGH_SVC_DT DATETIME
		SET @HIGH_SVC_DT = (SELECT MAX(CDML_TO_DT) FROM FACETS_STG.dbo.STG_CMC_CDML WHERE CLCL_ID = @CLCL_ID GROUP BY CLCL_ID)

		DECLARE @TOT_CHG MONEY
		SET @TOT_CHG = (SELECT SUM(CDML_CHG_AMT) FROM FACETS_STG.dbo.STG_CMC_CDML WHERE CLCL_ID = @CLCL_ID GROUP BY CLCL_ID)
			
		UPDATE FACETS_STG.dbo.STG_CMC_CLCL
		SET
			CLCL_LOW_SVC_DT		= @LOW_SVC_DT,
			CLCL_HIGH_SVC_DT	= @HIGH_SVC_DT,
			CLCL_TOT_CHG		= @TOT_CHG
		WHERE CLCL_ID = @CLCL_ID

		/* Step Log - Setting completion status and description for step log */
		SELECT @rows_processed	= @@ROWCOUNT,
			   @status_desc		= @step_desc + ' COMPLETED',
			   @status			= 'C'	
			   
		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

		COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

		SELECT @error			= ERROR_NUMBER(), -- NON ZERO
			   @sys_def_msg		= ERROR_MESSAGE(),
			   @status_desc		= @step_desc + ' Failed.',
			   @status			= 'E'

        -- Rollback the transaction in case of an error
        ROLLBACK TRANSACTION;
        
  		/* Execute dbo.USP_CLM_STEP_ERR_LOG Stored Procedure to insert step details and Error Details if Failed. */
		EXEC dbo.USP_CLM_STEP_ERR_LOG @run_id			= @run_id,
									  @job_id			= @job_id,
									  @status_desc		= @status_desc,
									  @sys_def_msg		= @sys_def_msg,
									  @step_id			= @step_id,
									  @sp_name			= @sp_name,
									  @error			= @error,
									  @rows_processed	= @rows_processed,
									  @status			= @status

    END CATCH;

END
GO
-------------------------------------------------------------------------------------------------------------------------------

-- Declare a variable of the table type (CLAIM-1 - Single Claim Line with Accepted Date range)
DECLARE @LINE_DATA STG_CMC_CDML_TYPE
DECLARE @CLPR_DATA STG_CMC_CLPR_TYPE;
-- Insert sample data into the table variable
INSERT INTO @LINE_DATA (CDML_CHG_AMT, CDML_FROM_DT, CDML_TO_DT, DIAG_CD, PROC_CD)
VALUES (230.00, '2025-01-05', '2025-01-09', 'P130','G1018')
-- Insert sample data into the table variable
INSERT INTO @CLPR_DATA (CLPR_TYPE,CLPR_TAX,CLPR_NPI,CLPR_STATE)
VALUES ('85', 'MI0125E19F','841560125', 'MI')
-- Execute the stored procedure   
EXEC [dbo].[USP_CLM_LOAD_STG_DATA] 'H','I','44299233','Scott','White','F','1991-04-06', @LINE_DATA = @LINE_DATA, @CLPR_DATA = @CLPR_DATA
GO
-- Declare a variable of the table type (CLAIM-2 - Multiple Line claim with Accepted Date range)
DECLARE @LINE_DATA STG_CMC_CDML_TYPE
DECLARE @CLPR_DATA STG_CMC_CLPR_TYPE;
-- Insert sample data into the table variable
INSERT INTO @LINE_DATA (CDML_CHG_AMT, CDML_FROM_DT, CDML_TO_DT, DIAG_CD, PROC_CD)
VALUES (664.33, '2024-12-22', '2024-12-24', 'P130','G1018'),
  (86.00, '2024-12-22', '2024-12-29', 'D01','G1001'),
  (855.00, '2024-12-27', '2024-12-31', 'H551','HP031');
-- Insert sample data into the table variable
INSERT INTO @CLPR_DATA (CLPR_TYPE,CLPR_TAX,CLPR_NPI,CLPR_STATE)
VALUES ('85', 'MI0125E19F','841560125', 'MI')
-- Execute the stored procedure    
EXEC [dbo].[USP_CLM_LOAD_STG_DATA] 'M','I','5584662','Scott','White','F','1991-04-06', @LINE_DATA = @LINE_DATA, @CLPR_DATA = @CLPR_DATA
GO
--------------------------------------------------------------------------------------------------------------
--TRUNCATE TABLE FACETS_STG..STG_CMC_CLCL
--TRUNCATE TABLE FACETS_STG..STG_CMC_CDML
--TRUNCATE TABLE FACETS_STG..STG_CMC_CLPR
--TRUNCATE TABLE FACETS_STG..STG_CMC_MEME
--TRUNCATE TABLE dbo.CLM_JOB_STEP_LOG
--TRUNCATE TABLE dbo.CLM_JOB_ERR_LOG
SELECT * FROM FACETS_STG..STG_CMC_CLCL
SELECT * FROM FACETS_STG..STG_CMC_CDML
SELECT * FROM FACETS_STG..STG_CMC_CLPR
SELECT * FROM FACETS_STG..STG_CMC_MEME
SELECT * FROM dbo.CLM_JOB_STEP_LOG
SELECT * FROM dbo.CLM_JOB_ERR_LOG

SELECT * FROM [dbo].[CMC_MEME]