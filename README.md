# General structure

* a VPC (10.0.0.0/16)
* DMZ subnet (10.0.1.0/24) with NAT Gateway 
* Private subnet (10.0.2.0/24)
* (optional) S3 bucket

## Costs
* NAT Gateway not free
* S3 Storage: free if the storage <= 5GB

## Accessing EC2 instances
### 1. Public jumpbox (DMZ)
- Use SSH
```bash 
ssh -i <key.pem> ubuntu@<public-ip>
```
### 2. Private box (internal)
```bash
scp -i <key.pem> <file-to-copy> ubuntu@<private-ip>:</path-for-file>
```

