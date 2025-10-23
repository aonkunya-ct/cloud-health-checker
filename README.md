# ☁️ Cloud Health Checker

> An automated website health checker built with Go, deployed on AWS Lambda, and managed by Terraform (IaC).

This project is an automated system that periodically checks the HTTP status of a list of websites to ensure they are online and operational. It reads the list of URLs from an AWS S3 bucket and runs on a schedule (every 5 minutes) using AWS Lambda and EventBridge. All infrastructure is provisioned using Terraform.

---

## 🛠️ Technologies Used

This project utilizes a modern cloud-native stack:

* **Programming Language:**
    * [Go (Golang)](https://go.dev/)
* **AWS Cloud Services:**
    * **[AWS Lambda](https://aws.amazon.com/lambda/):** For serverless compute (runs the Go code)
    * **[Amazon S3](https://aws.amazon.com/s3/):** To store the `urls.txt` config file
    * **[Amazon EventBridge](https://aws.amazon.com/eventbridge/):** As a scheduler (triggers the Lambda every 5 minutes)
    * **[Amazon CloudWatch](https://aws.amazon.com/cloudwatch/):** For logging the function's output
    * **[AWS IAM](https://aws.amazon.com/iam/):** To manage all necessary permissions (Roles & Policies)
* **Infrastructure as Code (IaC):**
    * **[Terraform](https://www.terraform.io/):** To define, provision, and manage all AWS resources automatically

---

## 🏗️ Architecture

The system follows a simple, event-driven, serverless architecture:

1.  An **Amazon EventBridge** rule triggers "every 5 minutes".
2.  EventBridge invokes the **AWS Lambda** function.
3.  The **Go program** (running on Lambda) loads its AWS config and S3 client.
4.  It fetches the `urls.txt` file from the **S3 Bucket**.
5.  **[ปรับปรุง]** It loops through each URL, **trims whitespace, skips empty lines**, and performs an HTTP GET request (`checkUrl` function) **with a 10-second timeout.**
6.  It logs the `Status: OK` or `Status: Not OK` output to **Amazon CloudWatch Logs**.

---

## 🚀 How to Deploy

All infrastructure is managed by Terraform.

**Prerequisites:**
* [Terraform](https://developer.hashicorp.com/terraform/install) installed
* [AWS CLI](https://aws.amazon.com/cli/) installed and configured (`aws configure`)
* [Go](https://go.dev/doc/install) (1.x) installed

**Deployment Steps:**

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/YOUR_USERNAME/cloud-health-checker.git](https://github.com/YOUR_USERNAME/cloud-health-checker.git)
    cd cloud-health-checker
    ```

2.  **Create the S3 Bucket (Manual Step):**
    * Create an S3 bucket in the `ap-southeast-1` region (e.g., `cloud-health-checker`) for the config file.
    * *(Note: This step is manual, but could be integrated into Terraform with state management.)*

3.  **Upload the URL List:**
    * Create a `urls.txt` file in the root directory.
    * Upload it to your S3 bucket:
        ```bash
        aws s3 cp urls.txt s3://cloud-health-checker/urls.txt
        ```

4.  **Prepare the Go Binary for Lambda:**
    * Compile the Go program for Linux (which Lambda uses):
        ```bash
        # For Windows (CMD)
        set GOOS=linux && set GOARCH=amd64 && go build -o bootstrap main.go

        # For macOS/Linux
        GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
        ```
    * Zip the binary file (this `bootstrap` file ⚙️ is what we deploy):
        ```bash
        # For Windows (PowerShell/CMD)
        # (You can use 7-Zip or Windows' "Send to -> Compressed folder" and rename it)

        # For macOS/Linux
        zip lambda_function.zip bootstrap
        ```

5.  **Deploy with Terraform:**
    * Initialize Terraform to download the AWS provider:
        ```bash
        terraform init
        ```
    * Plan the deployment:
        ```bash
        terraform plan
        ```
    * Apply the plan to create all 7 AWS resources:
        ```bash
        terraform apply
        ```

6.  **Verify:**
    * After 5-10 minutes, check the **CloudWatch Log Group** `/aws/lambda/cloud-health-checker-function` to see the health check logs.

---

## 💡 Key Learnings & Troubleshooting

This project was a great exercise in cloud engineering. Key challenges included:

* **HTTP Request Timeout:** Ensuring stability by explicitly setting a **10-second timeout** on the `http.Client` to prevent the Lambda function from running until its overall limit is reached due to slow or unresponsive websites.
* **IAM Permissions:** Debugging `AccessDenied` errors for both the S3 bucket (for Terraform) and the Lambda Role (e.g., needing `s3:GetObject` and `logs:PutLogEvents`).
* **S3 Region Redirect:** Solving the `301 PermanentRedirect` error by explicitly setting the correct AWS region (`ap-southeast-1`) in both the Go SDK and the Terraform provider.
* **Lambda Runtimes:** AWS deprecated the `go1.x` runtime, forcing a migration to the `provided.al2` runtime. This required compiling the Go code to a binary named `bootstrap` instead of deploying the source code.
* **Cross-Platform Issues:** Handling Windows `\r\n` (Carriage Return) characters in the `urls.txt` file by adding `strings.ReplaceAll` to sanitize the input.