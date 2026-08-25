# Database Initialization Strategy

**Last Updated:** 2026-06-05
**Jira:** PETPLAT-24
**Related:** PETPLAT-22, PETPLAT-25, PETPLAT-26

---

## Purpose

Describes how the shared `petclinic` MySQL database is initialized when deploying the Spring Petclinic Microservices to AWS RDS for the first time.

---

## Table of Contents

1. [Strategy](#strategy)
2. [Shared Database Design](#shared-database-design)
3. [Schema Overview](#schema-overview)
4. [Initialization Order](#initialization-order)
5. [Connection String Format](#connection-string-format)
6. [Kubernetes ConfigMap Example](#kubernetes-configmap-example)
7. [Verification](#verification)

---

## Strategy

**Spring Boot auto-initialization** is used. Each service declares its schema SQL in `src/main/resources/db/mysql/schema.sql`. When `spring.sql.init.mode=always` is active under the `mysql` Spring profile, Spring Boot executes these scripts on startup.

This approach:
- Requires no external init job or manual SQL execution
- Is idempotent (`CREATE TABLE IF NOT EXISTS`, `CREATE DATABASE IF NOT EXISTS`)
- Enforces correct order by controlling deployment sequence (customers before visits)

No init container, no manual SQL runner, no Flyway/Liquibase is needed for this project.

---

## Shared Database Design

All three database-backed services share a **single `petclinic` database** on one RDS MySQL 8.0 instance.

| Service | Tables Created | Notes |
|---------|---------------|-------|
| `customers-service` | `types`, `owners`, `pets` | Must initialize first — `pets` is FK target |
| `vets-service` | `vets`, `specialties`, `vet_specialties` | Independent, can run in parallel with customers |
| `visits-service` | `visits` | Requires `pets` table from customers-service |

**Why shared?** The `visits` table has `FOREIGN KEY (pet_id) REFERENCES pets(id)`. The `pets` table is owned by `customers-service`. This cross-service FK constraint confirms the application was designed with a single database in mind. See ADR-0003.

---

## Schema Overview

### Customers Service (3 tables)

```sql
CREATE DATABASE IF NOT EXISTS petclinic;
USE petclinic;

CREATE TABLE IF NOT EXISTS types (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80));
CREATE TABLE IF NOT EXISTS owners (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, first_name VARCHAR(30), last_name VARCHAR(30), address VARCHAR(255), city VARCHAR(80), telephone VARCHAR(20));
CREATE TABLE IF NOT EXISTS pets (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(30), birth_date DATE, type_id INT NOT NULL, owner_id INT NOT NULL,
  FOREIGN KEY (owner_id) REFERENCES owners(id),
  FOREIGN KEY (type_id)  REFERENCES types(id));
```

### Vets Service (3 tables)

```sql
CREATE TABLE IF NOT EXISTS vets (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, first_name VARCHAR(30), last_name VARCHAR(30));
CREATE TABLE IF NOT EXISTS specialties (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, name VARCHAR(80));
CREATE TABLE IF NOT EXISTS vet_specialties (vet_id INT NOT NULL, specialty_id INT NOT NULL,
  FOREIGN KEY (vet_id)       REFERENCES vets(id),
  FOREIGN KEY (specialty_id) REFERENCES specialties(id));
```

### Visits Service (1 table)

```sql
CREATE TABLE IF NOT EXISTS visits (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, pet_id INT NOT NULL, visit_date DATE, description VARCHAR(8192),
  FOREIGN KEY (pet_id) REFERENCES pets(id));  -- requires customers-service schema first
```

---

## Initialization Order

**Critical:** Deploy services in this sequence to satisfy FK constraints:

1. **customers-service** — creates `types`, `owners`, `pets`
2. **vets-service** — creates `vets`, `specialties`, `vet_specialties` (independent of customers)
3. **visits-service** — creates `visits` (depends on `pets` existing)

In Kubernetes, this is enforced by `initContainers` that wait for upstream services. The visits-service Deployment uses an init container to wait for the customers-service to become healthy before starting (ensuring `pets` is created before `visits` init runs).

---

## Connection String Format

```
jdbc:mysql://{rds-endpoint}:3306/petclinic
```

**Example (dev):**
```
jdbc:mysql://petclinic-dev-mysql.abc123.us-east-1.rds.amazonaws.com:3306/petclinic
```

Retrieve the actual endpoint after `terraform apply`:

```bash
terraform output rds_endpoint    # from terraform/environments/dev/
terraform output rds_connection_string
```

---

## Kubernetes ConfigMap Example

Each database-backed service includes a ConfigMap with the datasource URL:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: customers-service-config
  namespace: petclinic-dev
data:
  SPRING_DATASOURCE_URL: "jdbc:mysql://petclinic-dev-mysql.abc123.us-east-1.rds.amazonaws.com:3306/petclinic"
  SPRING_PROFILES_ACTIVE: "docker,mysql"
  CONFIG_SERVER_URL: "http://config-server:8888"
```

Credentials (`SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`) come from the Kubernetes Secret synced by External Secrets Operator — they are **never** in ConfigMaps.

---

## Verification

After `terraform apply` and service deployment:

```bash
# 1. Confirm RDS is available
aws rds describe-db-instances --db-instance-identifier petclinic-dev-mysql \
  --query 'DBInstances[0].DBInstanceStatus'

# 2. Confirm credentials are in Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id petclinic/dev/rds-credentials \
  --query SecretString

# 3. Test connectivity from an EKS debug pod
kubectl run mysql-debug --rm -it --restart=Never \
  --image=mysql:8.0 \
  -- mysql -h <rds-endpoint> -u petclinic -p

# 4. Verify tables exist (run inside MySQL shell)
USE petclinic;
SHOW TABLES;
# Expected: types, owners, pets, vets, specialties, vet_specialties, visits
```
