USE [FACETS];
GO

CREATE TABLE dbo.CMC_CLCL
(
    CLCL_ID             VARCHAR(10),
    MEME_CK             INT,
    MEME_ID             INT,
    CLCL_SUB_TYPE       VARCHAR(1),
    CLCL_TOT_CHG        MONEY,
    CLCL_TOT_PAYABLE    MONEY,
    CLCL_NTWK_IND       VARCHAR(1),
    PRPR_ID              VARCHAR(10),
    CLCL_CUR_STS        VARCHAR(2),
    CLCL_LOW_SVC_DT     DATETIME,
    CLCL_HIGH_SVC_DT    DATETIME,
    CLCL_PA_ACCT_NO     VARCHAR(7),
    CLCL_INPUT_DT       DATETIME,

    PRIMARY KEY (CLCL_ID)
);
GO

SELECT *
FROM dbo.CMC_CLCL;

---------------------------------------------------------

CREATE TABLE dbo.CMC_CDML
(
    CLCL_ID             VARCHAR(10),
    CDML_SEQ            SMALLINT,
    CDML_SUB_TYPE       VARCHAR(1),
    CDML_CHG_AMT        MONEY,
    CDML_NTWK_IND       VARCHAR(1),
    CDML_FROM_DT        DATETIME,
    CDML_TO_DT          DATETIME,
    CDML_ALLOW          MONEY,
    CDML_DISALLOW       MONEY,
    CDML_DISALLOW_EXCD  VARCHAR(7),
    DIAG_CD             VARCHAR(7),
    PROC_CD             VARCHAR(7),
    PRPR_ID             VARCHAR(10),
    CDML_CUR_STS        VARCHAR(2),
    CDML_INPUT_DT       DATETIME,

    PRIMARY KEY (CLCL_ID, CDML_SEQ)
);
GO

SELECT * FROM CMC_CDML

-------------------------------------------------------------


CREATE TABLE dbo.CMC_CLOV
(
    CLCL_ID         VARCHAR(10),
    PRPR_ID         VARCHAR(10),
    CLOV_AMT        MONEY,
    ACPR_REF_ID     VARCHAR(10),
    CLOV_CREATE_DT  DATETIME,

    PRIMARY KEY (CLCL_ID, ACPR_REF_ID)
);
GO

SELECT * FROM dbo.CMC_CLOV

-----------------------------------------------------------


CREATE TABLE dbo.CMC_ACPR
(
    ACPR_REF_ID      VARCHAR(10),
    ACPR_TYPE        VARCHAR(2),
    ACPR_SUB_TYPE    VARCHAR(1),
    ACPR_CREATE_DT   DATETIME,
    ACPR_PAYEE_ID    VARCHAR(10),
    ACPR_STS         VARCHAR(1),
    ACPR_ORIG_AMT    MONEY,
    ACPR_NET_AMT     MONEY,
    ACPR_RECOV_AMT   MONEY,
    ACPR_WOFF_AMT    MONEY,
    EXCD_ID          VARCHAR(3),

    PRIMARY KEY (ACPR_REF_ID, ACPR_TYPE, ACPR_SUB_TYPE)
);
GO

SELECT * FROM dbo.CMC_ACPR



CREATE TABLE dbo.CMC_ACRH
(
    ACPR_REF_ID        VARCHAR(10),
    ACPR_TYPE          VARCHAR(2),
    ACPR_SUB_TYPE      VARCHAR(1),
    ACRH_CREATE_DT     DATETIME,
    ACRH_EVENT_TYPE    VARCHAR(1),
    ACRH_AMT           MONEY,
    ACRH_MCTR_RSN      VARCHAR(10),

    PRIMARY KEY (ACPR_REF_ID, ACPR_SUB_TYPE)
);
GO

SELECT * FROM dbo.CMC_ACRH

------------------------------------------------------


CREATE TABLE dbo.CMC_PRWM
(
    PRPR_ID         VARCHAR(10),
    PRWM_EFF_DT     DATETIME,
    PRWM_TERM_DT    DATETIME,
    WMDS_SEQ_NO     VARCHAR(4),

    PRIMARY KEY (PRPR_ID, WMDS_SEQ_NO)
);
GO

------------------------------------------------------
