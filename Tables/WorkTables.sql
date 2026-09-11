USE [FACETS_Custom];
GO

/*===========================================================
  TABLE: dbo.CW_HEADER
  PURPOSE: Store claim workflow/header information
===========================================================*/

CREATE TABLE dbo.CW_HEADER
(
    ACPR_REF_ID       VARCHAR(10) NOT NULL,
    ACPR_TYPE         VARCHAR(2)  NOT NULL,
    ACPR_SUB_TYPE     VARCHAR(1)  NOT NULL,
    ACPR_CREATE_DT    DATETIME    NULL,
    STATUS            VARCHAR(20) NULL,
    UPDT_DTM          DATETIME    NULL,
    LAST_LTR_DT       DATETIME    NULL,
    ACPR_NET_AMT      MONEY       NULL,

    CONSTRAINT PK_CW_HEADER
        PRIMARY KEY
        (
            ACPR_REF_ID,
            ACPR_TYPE,
            ACPR_SUB_TYPE
        )
);
GO

USE [FACETS_Custom];
GO

CREATE TABLE dbo.CW_STATUS
(
    ACPR_REF_ID       VARCHAR(10) NOT NULL,
    ACPR_TYPE         VARCHAR(2)  NOT NULL,
    ACPR_SUB_TYPE     VARCHAR(1)  NOT NULL,
    STATUS            VARCHAR(20) NULL,
    UPDT_DTM          DATETIME    NULL
);
GO



CREATE TABLE dbo.CW_RJCT_CLCL
(
    CLCL_ID             VARCHAR(10)  NULL,
    MEME_CK             INT          NULL,
    CLCL_SUB_TYPE       VARCHAR(1)   NULL,
    CLCL_TOT_CHG        MONEY        NULL,
    PRPR_ID             VARCHAR(10)  NULL,
    CLCL_PA_ACCT_NO     VARCHAR(7)   NULL,
    RJCT_REAS           VARCHAR(255) NULL,
    UPDT_DTM            DATETIME     NULL
);
GO