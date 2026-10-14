# AWS Serverless Order Processing & Invoicing Pipeline

[![AWS Lambda](https://img.shields.io/badge/Compute-AWS%20Lambda-FF9900?logo=awslambda&logoColor=white)](https://aws.amazon.com/lambda/)
[![AWS Step Functions](https://img.shields.io/badge/Orchestration-AWS%20Step%20Functions-FF4F8B?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/step-functions/)
[![Amazon SQS](https://img.shields.io/badge/Messaging-Amazon%20SQS-FF4F8B?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/sqs/)
[![Amazon S3](https://img.shields.io/badge/Storage-Amazon%20S3-569A31?logo=amazons3&logoColor=white)](https://aws.amazon.com/s3/)
[![Amazon SES](https://img.shields.io/badge/Notifications-Amazon%20SES-D16A28?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/ses/)
[![Amazon RDS](https://img.shields.io/badge/Database-Amazon%20RDS%20MySQL-4479A1?logo=mysql&logoColor=white)](https://aws.amazon.com/rds/)
[![Amazon API Gateway](https://img.shields.io/badge/API-API%20Gateway-8C4FFF?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/api-gateway/)

An enterprise-grade, event-driven serverless architecture for automated sales order ingestion, stateful orchestration, PDF receipt rendering, cloud archival, and customer notification dispatch. 

The entire cloud infrastructure (IAM, RDS, S3, SQS, SES, Lambda Layers, 8 Lambda functions, Step Functions State Machine, and API Gateway REST endpoints) is automated via declarative and reproducible provisioning scripts.

---

## Architecture Flow

```
                      [ Client / REST Request ]
                                  │
                                  ▼
                   ┌──────────────────────────────┐
                   │   Amazon API Gateway (REST)  │
                   └──────────────┬───────────────┘
                                  │ (POST /notas)
                                  ▼
                   ┌──────────────────────────────┐
                   │    AWS Lambda (notas)        │
                   │   Writes order to RDS DB     │
                   └──────────────┬───────────────┘
                                  │
                                  ▼
                   ┌──────────────────────────────┐
                   │   Amazon SQS (Order Queue)   │
                   └──────────────┬───────────────┘
                                  │ Event Source Mapping (Batch=1)
                                  ▼
                   ┌──────────────────────────────┐
                   │  AWS Lambda (sqs_trigger)    │
                   │  Starts Step Function Exec   │
                   └──────────────┬───────────────┘
                                  │
                                  ▼
      ┌────────────────────────────────────────────────────────┐
      │          AWS Step Functions State Machine              │
      │                                                        │
      │   ┌────────────────────────────────────────────────┐   │
      │   │ 1. Task: GenerarPDF (AWS Lambda)               │   │
      │   │    - Fetches order, client, & product data     │   │
      │   │    - Renders binary PDF via FPDF2              │   │
      │   └───────────────────────┬────────────────────────┘   │
      │                           ▼                            │
      │   ┌────────────────────────────────────────────────┐   │
      │   │ 2. Task: SubirS3 (AWS Lambda)                  │   │
      │   │    - Stores PDF in S3: {rfc}/{folio}.pdf       │   │
      │   │    - Attaches custom metadata & headers        │   │
      │   └───────────────────────┬────────────────────────┘   │
      │                           ▼                            │
      │   ┌────────────────────────────────────────────────┐   │
      │   │ 3. Task: EnviarEmail (AWS Lambda)              │   │
      │   │    - Dispatches branded email via Amazon SES   │   │
      │   │    - Updates S3 delivery metadata timestamps   │   │
      │   └────────────────────────────────────────────────┘   │
      └────────────────────────────────────────────────────────┘
```

---

## AWS Services & Architecture Breakdown

### 1. Amazon API Gateway & CRUD Micro-Lambdas
* **`/clientes`**: Customer entity management (CRUD) with tax RFC validation and relational integrity checks.
* **`/clientes/{id}/domicilios` & `/domicilios`**: Customer shipping/billing address management.
* **`/productos`**: Product catalog, inventory management, and pricing.
* **`/notas`**: Order creation. Verifies product inventory, computes line-item subtotal and tax, commits the transaction to RDS MySQL, and pushes an event payload to Amazon SQS.

### 2. Event Decoupling & Queue Ingestion (Amazon SQS)
* Asynchronous message queuing buffers purchase requests during traffic bursts.
* Event source mapping triggers `sqs_trigger` Lambda with batch sizing to prevent downstream throttling.

### 3. Stateful Orchestration (AWS Step Functions)
Orchestrates sequential, fault-tolerant execution across three dedicated functions:
1. **`generar_pdf`**: Reads order details from RDS and synthesizes a high-fidelity PDF invoice in memory.
2. **`subir_s3`**: Uploads binary document to an encrypted Amazon S3 bucket with strict object key hierarchy (`{rfc}/{folio}.pdf`) and operational metadata tags (`hora-envio`, `nota-descargada`, `veces-enviado`).
3. **`enviar_email`**: Integrates with Amazon Simple Email Service (SES) to send templated HTML emails with secure download links, and atomically updates S3 object metadata.

### 4. Custom Lambda Layer (`deps.zip`)
* Centralized shared runtime package containing `PyMySQL`, `fpdf2`, and common database connector helpers.
* Drastically minimizes individual Lambda deployment bundle sizes and execution cold-start latency.

---

## Repository Structure

```
├── lambdas/
│   ├── clientes/           # Customer management handler
│   ├── domicilios/         # Address management handler
│   ├── enviar_email/       # SES email dispatch & S3 metadata updater
│   ├── generar_pdf/        # PDF document generator (FPDF2)
│   ├── notas/              # Order creation & SQS ingestion handler
│   ├── productos/          # Catalog inventory handler
│   ├── sqs_trigger/        # SQS consumer triggering Step Functions
│   ├── subir_s3/           # S3 object persistence handler
│   └── shared/             # Shared DB connection pool & JSON serializers
├── sql/
│   └── init.sql            # Relational schema (clients, addresses, products, orders)
├── step-function-definition.json # Declarative Amazon States Language definition
├── setup.sh                # End-to-end automated cloud provisioning script
├── cleanup.sh              # Safe resource teardown script
├── config.sh.example       # Environment parameters template
├── test-api.sh             # Integration test suite validating the entire flow
└── README.md
```

---

## Automated Deployment

### Prerequisites
- AWS CLI configured with active credentials (`aws configure` or SSO).
- `jq` and `zip` installed locally.

### 1. Configuration
Copy the configuration template and customize parameters:
```bash
cp config.sh.example config.sh
# Edit config.sh with your target region, database password, and SES verified email
```

### 2. Deploy Infrastructure & Services
Run the deployment script:
```bash
chmod +x setup.sh cleanup.sh test-api.sh
./setup.sh
```
The script will sequentially provision:
1. IAM execution roles and least-privilege security policies.
2. RDS MySQL database instance and VPC security groups.
3. Database schema tables and constraints from `sql/init.sql`.
4. Amazon S3 bucket with private access enforcement.
5. Amazon SQS order queue.
6. Amazon SES email identity.
7. Reusable Lambda Layer packaging Python dependencies.
8. 8 Lambda microservices with environment variables.
9. AWS Step Functions State Machine.
10. Event Source Mapping between SQS and `sqs_trigger`.
11. Amazon API Gateway with all routes, methods, and deployment stages.

---

## Testing & Verification

Once deployed, run the automated integration test script:
```bash
./test-api.sh <API_ENDPOINT_URL>
```
The test verifies:
- Creation of clients, addresses, and catalog items.
- Placing a new purchase order (`POST /notas`).
- SQS message dispatch and Step Functions execution status.
- S3 object upload and SES delivery confirmation.

---

## Teardown

To cleanly destroy all provisioned AWS cloud resources:
```bash
./cleanup.sh
```

---

## Author
**Luis Alberto González Escamilla**  
Software & Systems Engineer · AI Agents & Cloud Solutions
