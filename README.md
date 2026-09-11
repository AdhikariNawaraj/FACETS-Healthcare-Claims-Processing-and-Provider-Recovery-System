# FACETS-Healthcare-Claims-Processing-and-Provider-Recovery-System
End-to-end SQL Server healthcare claims processing system covering claim staging, member/provider validation, adjudication, payment processing, provider recovery, collection letters, write-offs, rejection handling, and audit/error logging.
-------------------------------------------------------------------------------------------------------------------------------------------------------------------

Executive Summary:
*****************
The FACETS Healthcare Claims Processing Project is a SQL Server–based claims-processing solution designed to simulate how a healthcare payer receives, validates, adjudicates, pays, recovers, and closes medical claims.

The solution uses three logical database area:

| Database        | Primary purpose                                                                      |
| --------------- | ------------------------------------------------------------------------------------ |
| `FACETS_STG`    | Receives incoming claim, member, provider, and claim-line data                       |
| `FACETS`        | Stores validated claims and core operational/payment data                            |
| `FACETS_Custom` | Supports workflow, rejected claims, collection activities, and process/error logging |

The project begins when a healthcare claim is submitted. Incoming information is separated into claim header, claim detail, member, and provider staging tables. A sequence of stored procedures then validates the member, provider, service dates, and provider tax information. This reflects the project's adjudication requirements, which call for checks involving member/provider information, dates, eligibility, codes, and reimbursement information.

Claims that fail validation are assigned a rejection status and captured for reporting. Claims that pass all validations are moved from staging into the FACETS core tables and become eligible for payment processing.

Payment processing calculates allowable and disallowed amounts at the claim-line level. When an adjustment creates a provider receivable, an CMC_ACPR record is established to track the original amount, recovered amount, write-off amount, and remaining balance.

The project then extends beyond ordinary claims adjudication into accounts receivable and provider recovery management. Providers can make partial recoveries, outstanding balances can enter the collection-letter process, and qualifying small balances can ultimately be written off. CMC_ACRH, CW_HEADER, and CW_STATUS provide the supporting recovery and collection history.

Finally, common logging procedures record each processing step, row counts, execution status, and errors. This provides operational traceability across the entire claims lifecycle.




Final End-to- End Flow:

                  HEALTHCARE CLAIM RECEIVED
                            |
                            v
              +-----------------------------+
              |      CLAIM LOAD PROCESS     |
              |   USP_CLM_LOAD_STG_DATA     |
              +-----------------------------+
                            |
              +-------------+-------------+
              |             |             |
              v             v             v
       STG_CMC_CLCL   STG_CMC_CDML   STG_CMC_MEME
                                             |
                                             v
                                       STG_CMC_CLPR
                            |
                            v
              CLAIM STATUS = 16 (Submitted)
                            |
                            v
        +------------------------------------------+
        |          CLAIM VALIDATION FLOW           |
        +------------------------------------------+
                            |
                            v
                 1. MEMBER MATCH
                  USP_CLM_MBR_MTCH
                            |
                  +---------+---------+
                  |                   |
                PASS                 FAIL
                  |                   |
                  |            STATUS = 11
                  |            Member Not Found
                  |                   |
                  |                   v
                  |             REJECT CLAIM
                  |
                  v
                2. PROVIDER MATCH
                    Provider SP
                  |
          +-------+-------+
          |               |
        PASS             FAIL
          |               |
          |          STATUS = 12
          |          Provider Not Found
          |               |
          |               v
          |          REJECT CLAIM
          |
          v
          
             3. SERVICE DATE VALIDATION
                 USP_CLM_SVCDT_VAL
                         |
                         
                +--------+--------+
                
                |                 |
                
              PASS               FAIL
              
                |                 |
                |            STATUS = 13
                |            Invalid Service
                |            Date Span
                |                 |
                
                |                 v
                |            REJECT CLAIM
                |
                v

                
                4. TAX ID VALIDATION
                    USP_CLM_TAXID_VAL
                    
                         |
                         
                +--------+--------+
                |                 |
              PASS               FAIL
              
                |                 |
                
                |            STATUS = 14
                |            Invalid Tax ID
                
                |                 |
                
                |                 v
                |            REJECT CLAIM
                |
                v
                
          FINAL STAGING VALIDATION
                         |
             +-----------+-----------+
             |                       |
          VALID                     ERROR
             |                       |
             |                  STATUS = 15
             |                  Errored Out
             |
             v
             
             STAGING -> CORE
             USP_CLM_STG_TO_CORE
             
                     |
                     v
                     
              STATUS = 01
              Claim Loaded
                     |
          +----------+----------+
          |                     |
          
          v                     v
          
   CMC_CLCL                    CMC_CDML
 Claim Header                Claim Detail
 
          |
          v
          
       PAYMENT PROCESS
     USP_CLM_PYMT_PRCS
     
          |
          v
          
    Calculate line-level:
      CHARGE
      
         |
         
      DEDUCTION
      
         |
    +----+-----+
    |          |
    
  ALLOW     DISALLOW
    |          |
    
    +----+-----+
    
         |
         
         v
         
  Update Claim Payable
         |
         
    +----+--------------------+
    |                         |
    
    
No Reduction              Reduction/
                          Overpayment
                          
                          
    |                         |
    v                         v
    
STATUS = 02                 CMC_ACPR
Payment Successful      Recovery Receivable
                              |
                              v
                              
                     +-------------------+
                     | PROVIDER RECOVERY |
                     +-------------------+
                              |
                              v
                    USP_CLM_PYMT_RECOV
                              |
                              
                     Provider makes
                     partial recovery
                              |
                              
                 +------------+------------+
                 |                         |
                 
                 v                         v
                 
          ACPR_RECOV_AMT            ACPR_NET_AMT
             increases                decreases
                 |                         |
                 
                 +------------+------------+
                 
                              |
                              
                     Is NET AMT = $0?
                     
                         /          \
                       YES           NO
                       
                        |             |
                        
                        v             v
                        
                  ACPR_STS = I    ACPR_STS = A
                     Closed          Active
                     
                        |
                        
                        v
                    CMC_ACRH
                 Recovery History


              OUTSTANDING RECOVERIES
                        |
                        v
                        
              COLLECTION LETTER PROCESS
                 USP_CLM_COLL_LTR
                        |
                        
                        v
                  CW_HEADER
                 Current State
                        |
                        
                        v
                        
                   CW_STATUS
                  Status History
                        |
                        
              +---------+---------+
              |                   |
              
              v                   v
              
         PAR PROVIDER        NON-PAR / VA
         
              |                   |
              
              +---------+---------+
                        |
                        
                  Initial Letter
                  
                        |
                  Follow-up Letters
                  
                        |
                  Collection Stops
                        |
                        
              +---------+---------+
              |                   |
              
        Provider Pays       Balance Remains
              |                   |
              
              v                   v
        Recovery SP          WRITE-OFF
                         USP_CLM_PYMT_WROFF
                         
                                  |
                                  v
                                  
                         Provider-level
                         threshold check
                                  |
                                  
                                  v
                          ACPR_WOFF_AMT
                             increases
                                  |
                                  
                          ACPR_NET_AMT = 0
                                  |
                                  
                           ACPR_STS = I
                           
                                  |
                       +----------+----------+
                       |                     |
                       
                       v                     v
                       
                    CMC_ACRH             CW_STATUS
                Write-off History       WRITE-OFF
                                             |
                                             
                                             v
                                         CW_HEADER
                                           CLOSE


The project in 8 business stages:

1. Claim Intake: USP_CLM_LOAD_STG_DATA receives the claim and separates it into STG_CMC_CLCL, STG_CMC_CDML, STG_CMC_MEME, and STG_CMC_CLPR. The initial claim status is 16, indicating that the claim has been submitted to staging.

2. Member and Provider Matching: Member information is matched against CMC_MEME, followed by provider matching against the provider master. Your project materials specifically describe member matching and provider selection as major processing modules. A failed member match produces status 11; a failed provider match produces 12.

3. Preprocessing Validations: Service dates and provider tax information are validated. The service-date requirement specifically requires service-line dates to remain within the same calendar month and year; violations receive status 13. Tax failures receive status 14.

4. Stage-to-Core Processing: Claims surviving the validations move from FACETS_STG to the core FACETS claim tables and receive status 01. Rejected claims are retained in CW_RJCT_CLCL for reporting rather than being treated as successfully adjudicated claims.

5. Payment Processing: USP_CLM_PYMT_PRCS calculates line-level allowed/disallowed amounts and updates claim payable amounts. When a reduction creates a receivable, the procedure establishes CMC_ACPR and CMC_CLOV records. Successful claims ultimately receive status 02, while applicable zero-paid payment rejects use status 91.

6. Provider Recovery: USP_CLM_PYMT_RECOV allows a provider to make partial payments against an outstanding receivable. Each payment increases ACPR_RECOV_AMT and decreases ACPR_NET_AMT. Once the remaining balance reaches zero, the receivable becomes inactive (ACPR_STS='I').

   For Exmaple:
   Original Receivable       $1,000
        |
Provider pays $300
        v
Recovered = $300
Net       = $700
        |
Provider pays $400
        v
Recovered = $700
Net       = $300
        |
Provider pays $300
        v
Recovered = $1,000
Net       = $0
Status    = I

7. Collection Letter Processing: Outstanding recoveries enter USP_CLM_COLL_LTR. CW_HEADER maintains the current collection state while CW_STATUS captures collection events. PAR, NON-PAR, and VA providers follow the collection-letter timing rules from the workbook, including initial, follow-up, stop, hold, reopen, close, and void processing.

8. Write-Off and Closure: USP_CLM_PYMT_WROFF handles eligible balances that remain after collection activity. It evaluates the provider-level balance against the write-off requirement, transfers the outstanding balance into ACPR_WOFF_AMT, reduces ACPR_NET_AMT to zero, records the history, and closes the recovery.


Stored Procedure Execution Sequence

From a technical perspective, the intended execution order is:
/* ============================================================
   FACETS CLAIM PROCESSING - MASTER FLOW
   ============================================================ */

-- 1. Load incoming claim
EXEC FACETS_Custom.dbo.USP_CLM_LOAD_STG_DATA ...;


-- 2. Member Match
EXEC FACETS_Custom.dbo.USP_CLM_MBR_MTCH;


-- 3. Provider Match
EXEC FACETS_Custom.dbo.USP_CLM_PRV_MTCH;


-- 4. Service Date Validation
EXEC FACETS_Custom.dbo.USP_CLM_SVCDT_VAL;


-- 5. Tax ID Validation
EXEC FACETS_Custom.dbo.USP_CLM_TAXID_VAL;


-- 6. Move successful claims STG -> CORE
EXEC FACETS_Custom.dbo.USP_CLM_STG_TO_CORE;


-- 7. Process Payment
EXEC FACETS_Custom.dbo.USP_CLM_PYMT_PRCS
     @CLCL_ID = '...',
     @LINE_DATA = @LINE_DATA,
     @EXCD_ID = '...';


-- 8. Provider Recovery - when payment is received
EXEC FACETS_Custom.dbo.USP_CLM_PYMT_RECOV
     @CLCL_ID   = '...',
     @PRPR_ID   = '...',
     @RECOV_AMT = 300.00;


-- 9. Collection Letter Batch
EXEC FACETS_Custom.dbo.USP_CLM_COLL_LTR;


-- 10. Write-Off Batch
EXEC FACETS_Custom.dbo.USP_CLM_PYMT_WROFF;


The recovery, collection-letter, and write-off procedures are not necessarily executed immediately after payment. They represent downstream events. Recovery runs when money is received; collection processing runs according to aging/timing rules; write-off runs when the appropriate collection criteria have been reached.




Database Architecture:

                 SOURCE / CLAIM INPUT
                         |
                         v
+------------------------------------------------+
|                  FACETS_STG                    |
|                                                |
| STG_CMC_CLCL   Claim Header                    |
| STG_CMC_CDML   Claim Lines                     |
| STG_CMC_MEME   Member Information              |
| STG_CMC_CLPR   Provider Information            |
+------------------------------------------------+
                         |
                  Validation / ETL
                         |
                         v
+------------------------------------------------+
|                    FACETS                      |
|                                                |
| CMC_MEME   Member Master                       |
| CMC_PRPR   Provider Master                     |
| CMC_PRWM   Provider Warning/Window             |
| CMC_CLCL   Claim Header                        |
| CMC_CDML   Claim Detail                        |
| CMC_ACPR   Accounts Receivable / Recovery      |
| CMC_ACRH   Recovery History                    |
| CMC_CLOV   Claim-to-Recovery Offset            |
+------------------------------------------------+
                         |
                         v
+------------------------------------------------+
|                FACETS_Custom                   |
|                                                |
| CW_RJCT_CLCL       Rejected Claims             |
| CW_HEADER          Collection Current State    |
| CW_STATUS          Collection History          |
| CLM_JOB_STEP_LOG   Processing Audit            |
| CLM_JOB_ERR_LOG    Error Audit                 |
| Stored Procedures / Processing Logic           |
+------------------------------------------------+




Central Logging Framework:

               EVERY STORED PROCEDURE
                       |
              +--------+--------+
              |                 |
           SUCCESS             ERROR
              |                 |
              v                 v
    CLM_JOB_STEP_LOG    CLM_JOB_STEP_LOG
                              +
                       CLM_JOB_ERR_LOG



Claim Status Lifecycle:
The status codes make the complete claim lifecycle much easier to understand:

| Status | Meaning                            | Stage                               |
| -----: | ---------------------------------- | ----------------------------------- |
|   `16` | Claims Submitted                   | Staging                             |
|   `11` | Member Not Found                   | Member validation                   |
|   `12` | Provider Not Found                 | Provider validation                 |
|   `13` | Service Date Error                 | Preprocessing                       |
|   `14` | Provider Tax Error                 | Preprocessing                       |
|   `15` | Errored Out Claim                  | Final staging validation            |
|   `01` | Loaded to Core                     | Successful adjudication/pre-payment |
|   `02` | Successful Payment                 | Payment                             |
|   `91` | Payment Rejection / zero-paid case | Payment                             |

This demonstrates an important design principle: a claim does not simply pass or fail. Its status tells operations exactly where it is in the lifecycle and, when rejected, approximately where processing failed.
