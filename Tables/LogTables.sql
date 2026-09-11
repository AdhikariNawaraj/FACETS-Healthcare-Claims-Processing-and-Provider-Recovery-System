USE [FACETS_Custom]
GO

CREATE TABLE [dbo].[CLM_JOB_ERR_LOG]
(
	[RUN_ID] [int] NOT NULL,
	[JOB_ID] [varchar](255) NOT NULL,
	[SP_NAME] [varchar](255) NULL,
	[STEP_ID] [int] NULL,
	[USER_DEF_MSG] [varchar](5000) NULL,
	[SYS_DEF_MSG] [varchar](5000) NULL,
	[ERR_DTM] [datetime] NULL
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[CLM_JOB_STEP_LOG]
(
	[RUN_ID] [int] NOT NULL,
	[JOB_ID] [varchar](255) NOT NULL,
	[SP_NAME] [varchar](255) NULL,
	[STEP_ID] [int] NULL,
	[STEP_DESC] [varchar](5000) NULL,
	[STATUS] [varchar](1) NULL,
	[STEP_DTM] [datetime] NULL,
	[ROWS_PROCESSED] [int] NULL
) ON [PRIMARY]
GO