
/*Table - CMC_PRPR
**********************
Insert the data into CMC_PRPR table from adventure works 2022 database tables as mentioned below. 
Use the formats/criteria’s while inserting data into below specified formats by selection it from 
different tables from Adventuresworks2022 database.

P072600101
P072600102
P072600103

Column Name			              Value / Source Column 								   Table Name
------------					-----------------------									-----------------------
PRPR_ID				Generate in format - First Letter P, MMYY of the current date, 
					And 5 digit sequential No starting with 00101. 
					Example – P052600101, P052600102 etc.

PRPR_NAME			Concat First Name and Last Name with space in between					Person.Person

PRPR_NPI			National ID Number														HumanResources.Employee

MCTN_ID				Concat 2 CHARACTERS FROM StateProvinceCode,
					MMYY of the current date and First 4 Characters of rowguid Column		Person.StateProvince
																							HumanResources.Employee

PRPR_ADD1			AddressLine1															Person.Address

PRPR_ADD2			AddressLine2															Person.Address

PRPR_CITY			City																	Person.Address

PRPR_STATE			StateProvinceCode														Person.StateProvince

PRPR_CNTRY			CountryRegionCode														Person.StateProvince

PRPR_TERM_DT		Add 65 Years to BirthDate												HumanResources.Employee 
*/

-- Create Table
CREATE TABLE CMC_PRPR
(
	PRPR_ID			VARCHAR(20),
	PRPR_NAME		VARCHAR(100),
	PRPR_NPI		VARCHAR(20),
	MCTN_ID			VARCHAR(20),
	PRPR_ADD1		VARCHAR(100),
	PRPR_ADD2		VARCHAR(100),
	PRPR_CITY		VARCHAR(50),
	PRPR_STATE		VARCHAR(10),
	PRPR_CNTRY		VARCHAR(10),
	PRPR_TERM_DT	DATE
);

SELECT * FROM CMC_PRPR

-- INSERT DATA
;WITH CTE AS
(
    SELECT
        ROW_NUMBER() OVER(ORDER BY E.BusinessEntityID) + 100 AS SeqNo,

        P.FirstName,
        P.LastName,

        E.NationalIDNumber,
        E.BirthDate,

        A.AddressLine1,
        A.AddressLine2,
        A.City,

        SP.StateProvinceCode,
        SP.CountryRegionCode,
        SP.rowguid

    FROM HumanResources.Employee E

    INNER JOIN Person.Person P
        ON E.BusinessEntityID = P.BusinessEntityID

    INNER JOIN Person.BusinessEntityAddress BEA
        ON E.BusinessEntityID = BEA.BusinessEntityID

    INNER JOIN Person.Address A
        ON BEA.AddressID = A.AddressID

    INNER JOIN Person.StateProvince SP
        ON A.StateProvinceID = SP.StateProvinceID
)

INSERT INTO CMC_PRPR
(
    PRPR_ID,
    PRPR_NAME,
    PRPR_NPI,
    MCTN_ID,
    PRPR_ADD1,
    PRPR_ADD2,
    PRPR_CITY,
    PRPR_STATE,
    PRPR_CNTRY,
    PRPR_TERM_DT
)

SELECT

-- PRPR_ID
'P'
+ FORMAT(GETDATE(),'MMyy')
+ RIGHT('00000'+CAST(SeqNo AS VARCHAR(5)),5),

-- PRPR_NAME
CONCAT(FirstName,' ',LastName),

-- PRPR_NPI
NationalIDNumber,

-- MCTN_ID
LEFT(StateProvinceCode,2)
+ FORMAT(GETDATE(),'MMyy')
+ LEFT(REPLACE(CAST(rowguid AS VARCHAR(36)),'-',''),4),

-- Address1
AddressLine1,

-- Address2
AddressLine2,

-- City
City,

-- State
StateProvinceCode,

-- Country
CountryRegionCode,

-- Term Date
DATEADD(YEAR,65,BirthDate)

FROM CTE;

SELECT * FROM CMC_PRPR

--==================================================================================================================

/* Table - CMC_MEME
*******************
Insert the data into CMC_MEME table. Take the data from attached excel and load.
MEME_ID and MEME_PHONE will have some formats to generate data (Not from Excel)

Column	                        Value / Source Column
MEME_CK	ID                         (From Excel)
MEME_ID	                           Unique RANDOM 5 Digit number. Example 44222,55488
FIRST_NAME	                       First Name (From Excel)
LAST_NAME	                       Last Name (From Excel)
MID_INIT	                       MidInit (From Excel)
BIRTH_DT	                       DOB (From Excel – Take only Date part i.e. without time stamp)
MEME_PHONE	                       Generate random phone number in US format (XXX) xxx-xxxx. Example - (555) 013-5799
*/

-- CRATE Table

CREATE TABLE CMC_MEME
(
    MEME_CK     INT,
    MEME_ID     INT,
    FIRST_NAME  VARCHAR(50),
    LAST_NAME    VARCHAR(50),
    MID_INIT    VARCHAR(10),
    BIRTH_DT    DATE,
    MEME_PHONE  VARCHAR(20)
    );


-- CREATE STAGEING TABLE

CREATE TABLE STG_PERSON
(
    id  INT,
    first_name VARCHAR(50),
    last_name  VARCHAR(50),
    email      VARCHAR(100),
    MidInit    VARCHAR(50),
    dob        VARCHAR(30)
    );


-- LOAD Data
BULK INSERT STG_PERSON
FROM 'C:\Users\nwaad\OneDrive\Desktop\SQL_1031\SQL_server\Project_1031\Person.csv'
WITH
(
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0A',
    TABLOCK
);

-- INSERT INTO CMC_MEME

INSERT INTO CMC_MEME
(
    MEME_CK,
    MEME_ID,
    FIRST_NAME,
    LAST_NAME,
    MID_INIT,
    BIRTH_DT,
    MEME_PHONE
)
SELECT
    -- MEME_CK, from excel
    id,

    -- MEME_ID (5-digit sequential)
    50000 + ROW_NUMBER() OVER (ORDER BY id),

    -- First Name from excel
    first_name,

    -- Last Name from excel
    last_name,

    -- Middle Initial
    LEFT(MidInit, 1) AS MID_INIT,

    -- Birth Date
    TRY_PARSE(dob AS DATE USING 'en-US') AS BIRTH_DT,

    -- Random US Phone Number
    '('
    + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 900 + 100 AS VARCHAR(3)), 3)
    + ') '
    + RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 900 + 100 AS VARCHAR(3)), 3)
    + '-'
    + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4)

FROM STG_PERSON;
SELECT * FROM CMC_MEME





