```mermaid
graph TD
    A["Client (install.sh)"] -->|POST JSON| B["AWS API Gateway"]
    B -->|Trigger| C["AWS Lambda (Python)"]
    C -->|Write| D["AWS S3 (Storage)"]
```

