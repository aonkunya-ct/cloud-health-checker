# ------------------------------------------------------------------
# 1. การกำหนด Providers ที่ต้องใช้
# ------------------------------------------------------------------
terraform {
  required_providers {
    # กำหนดให้ใช้ AWS Provider
    aws = {
      source  = "hashicorp/aws" # AWS Provider อย่างเป็นทางการ
      version = "~> 5.0"        # กำหนดเวอร์ชันที่ต้องการ (5.x ขึ้นไป)
    }
  }
}

# ------------------------------------------------------------------
# 2. การตั้งค่า AWS Provider
# ------------------------------------------------------------------
provider "aws" {
  # กำหนด Region ของ AWS ที่ต้องการสร้างทรัพยากร
  # (สำคัญสำหรับการแก้ปัญหา S3 301 Redirect)
  region = "ap-southeast-1"
}

# ------------------------------------------------------------------
# 3. การสร้าง IAM Role สำหรับการประมวลผลของ Lambda
# ------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec_role" {
  name = "cloud-health-checker-role" # ชื่อ Role

  # Trust Policy: อนุญาตให้บริการ AWS Lambda (lambda.amazonaws.com) สวมสิทธิ์ (Assume Role) นี้ได้
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# ------------------------------------------------------------------
# 4. การสร้าง IAM Policy เพื่อเข้าถึง S3
# ------------------------------------------------------------------
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "cloud-health-checker-s3-policy"
  description = "Allow Lambda to read the urls.txt file from S3"

  # Policy Statements: อนุญาต (Allow) ให้เรียกใช้งาน Action s3:GetObject
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "s3:GetObject",
        Effect   = "Allow",
        Resource = "arn:aws:s3:::cloud-health-checker/urls.txt" # กำหนด Resource ที่อนุญาตให้เข้าถึง
      }
    ]
  })
}

# ------------------------------------------------------------------
# 5. การแนบ Policy S3 (ข้อ 4) เข้ากับ Role (ข้อ 3)
# ------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# ------------------------------------------------------------------
# 6. การสร้าง AWS Lambda Function
# ------------------------------------------------------------------
resource "aws_lambda_function" "health_checker_func" {
  function_name = "cloud-health-checker-function" # 1. กำหนดชื่อ Function

  # 2. กำหนดชื่อไฟล์ Zip ที่จะใช้ deploy (ต้องมีไฟล์ bootstrap ⚙️ อยู่ภายใน)
  filename = "lambda_function.zip"

  # 3. กำหนด Runtime เป็น provided.al2 (Custom Runtime) และ Handler คือชื่อ Binary file
  runtime = "provided.al2"
  handler = "bootstrap"

  # 4. ใช้ Role ที่สร้างในข้อ 3 สำหรับการทำงานของ Function
  role = aws_iam_role.lambda_exec_role.arn

  # 5. ติดตามการเปลี่ยนแปลงของไฟล์ Zip เพื่อกระตุ้นการอัปเดต Lambda Function
  source_code_hash = filebase64sha256("lambda_function.zip")
}

# ------------------------------------------------------------------
# 7. การสร้าง EventBridge Rule (ตัวกำหนดตารางเวลา)
# ------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "every_5_minutes" {
  name                = "every-5-minutes"
  description         = "Triggers the health checker every 5 minutes"
  
  # ตั้งเวลาการเรียกใช้ (ใช้รูปแบบ rate หรือ cron)
  schedule_expression = "rate(5 minutes)" 
}

# ------------------------------------------------------------------
# 8. การตั้งค่า Target ของ EventBridge Rule
# ------------------------------------------------------------------
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.every_5_minutes.name # 1. ใช้ Rule จากข้อ 7
  arn  = aws_lambda_function.health_checker_func.arn  # 2. กำหนดให้ Target คือ Lambda Function (ข้อ 6)
}

# ------------------------------------------------------------------
# 9. การให้สิทธิ์ EventBridge ในการเรียกใช้ Lambda
# ------------------------------------------------------------------
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction" # 1. สิทธิ์ในการ "เรียกใช้" (Invoke)
  function_name = aws_lambda_function.health_checker_func.function_name # 2. เรียกใช้ Lambda (ข้อ 6)
  principal     = "events.amazonaws.com" # 3. โดยบริการ EventBridge
  
  # 4. (เงื่อนไขสำคัญ) กำหนด Source ARN เพื่อจำกัดการ Invoked ให้มาจาก Rule ที่กำหนดเท่านั้น
  source_arn = aws_cloudwatch_event_rule.every_5_minutes.arn
}

# ------------------------------------------------------------------
# 10. การแนบ Policy สำหรับการเขียน CloudWatch Logs
# ------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "logs_attach" {
  role       = aws_iam_role.lambda_exec_role.name # 1. ติดให้กับ Role เดิม (ข้อ 3)
  
  # 2. Policy สำเร็จรูปของ AWS ที่อนุญาตให้เขียน Log Group/Events ได้
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}