USE [FACETS]
GO

/****** Object:  Table [dbo].[CMC_PRPR]    Script Date: 8/27/2026 7:51:30 PM ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CMC_PRPR]') AND type in (N'U'))
DROP TABLE [dbo].[CMC_PRPR]
GO

/****** Object:  Table [dbo].[CMC_PRPR]    Script Date: 8/27/2026 7:51:30 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[CMC_PRPR](
	[PRPR_ID] [varchar](20) NULL,
	[PRPR_NAME] [varchar](100) NULL,
	[PRPR_NPI] [varchar](20) NULL,
	[MCTN_ID] [varchar](20) NULL,
	[PRPR_ADD1] [varchar](100) NULL,
	[PRPR_ADD2] [varchar](100) NULL,
	[PRPR_CITY] [varchar](50) NULL,
	[PRPR_STATE] [varchar](10) NULL,
	[PRPR_CNTRY] [varchar](10) NULL,
	[PRPR_TERM_DT] [date] NULL
) ON [PRIMARY]
GO

INSERT INTO FACETS..CMC_PRPR
( PRPR_ID, PRPR_NAME, PRPR_NPI, MCTN_ID, PRPR_ADD1, PRPR_ADD2, PRPR_CITY, PRPR_STATE, PRPR_CNTRY, PRPR_TERM_DT)
SELECT 
 'P'+ FORMAT(GETDATE(), 'MMyy') + RIGHT('00000' + CAST(ROW_NUMBER() OVER (ORDER BY P.BusinessEntityID) + 100 AS VARCHAR(5)),5), 
 P.FirstName + ' ' + P.LastName,             
 E.NationalIDNumber,                
 CONCAT(S.StateProvinceCode,FORMAT(GETDATE(), 'MMyy'),LEFT(E.rowguid,4)),   
 A.AddressLine1,                    
 A.AddressLine2,                 
 A.City,                    
 S.StateProvinceCode,                    
 S.CountryRegionCode,                    
 DATEADD(YEAR,65,E.BirthDate)                 
FROM AdventureWorks2022.Person.Person P
JOIN AdventureWorks2022.HumanResources.Employee E ON P.BusinessEntityID = E.BusinessEntityID
JOIN AdventureWorks2022.Person.BusinessEntityAddress BE ON E.BusinessEntityID = BE.BusinessEntityID
JOIN AdventureWorks2022.Person.Address A ON BE.AddressID = A.AddressID
JOIN AdventureWorks2022.Person.StateProvince S ON A.StateProvinceID = S.StateProvinceID

SELECT * FROM CMC_PRPR