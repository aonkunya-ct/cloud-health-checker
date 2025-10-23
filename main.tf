# ------------------------------------------------------------------
# 1. บอก Terraform ว่าเราต้องการ "ปลั๊กอิน" อะไร
# ------------------------------------------------------------------
terraform {
  required_providers {
    # เราบอกว่า "เราต้องการใช้ AWS"
    aws = {
      source  = "hashicorp/aws" # ปลั๊กอิน AWS อย่างเป็นทางการ
      version = "~> 5.0"        # ระบุเวอร์ชัน (เอาเวอร์ชัน 5 ขึ้นไป)
    }
  }
}

# ------------------------------------------------------------------
# 2. ตั้งค่า "ปลั๊กอิน" AWS
# ------------------------------------------------------------------
provider "aws" {
  # บอกปลั๊กอินว่าให้ทำงานที่ Region ไหน
  # (นี่คือ Region ที่เราแก้ Error 301 กันไปครับ!)
  region = "ap-southeast-1"
}

# ------------------------------------------------------------------
# 3. สร้าง "บัตรอนุญาต" (IAM Role) ให้ Lambda
# ------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec_role" {
  name = "cloud-health-checker-role" # ตั้งชื่อ Role

  # นโยบาย "ความเชื่อใจ": 
  # "ฉันเชื่อใจให้ 'บริการ Lambda' (lambda.amazonaws.com) สวมรอย (Assume) Role นี้ได้"
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
# 4. สร้าง "Policy" (สิทธิ์) ที่บอกว่า Role นี้ทำอะไรได้บ้าง
# ------------------------------------------------------------------
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "cloud-health-checker-s3-policy"
  description = "Allow Lambda to read the urls.txt file from S3"

  # นโยบาย "สิทธิ์": 
  # "ฉันอนุญาต (Allow) ให้ 'อ่าน' (GetObject) จาก S3 bucket 'cloud-health-checker' ได้"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "s3:GetObject",
        Effect   = "Allow",
        Resource = "arn:aws:s3:::cloud-health-checker/urls.txt" # <-- ชี้ไปที่ไฟล์ของเรา!
      }
    ]
  })
}

# ------------------------------------------------------------------
# 5. "ติด" Policy (ข้อ 4) เข้ากับ Role (ข้อ 3)
# ------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# ------------------------------------------------------------------
# 6. สร้าง "Lambda Function" (ตัวโปรแกรม ⚙️)
# ------------------------------------------------------------------
resource "aws_lambda_function" "health_checker_func" {
  function_name = "cloud-health-checker-function" # 1. ตั้งชื่อ Function

  # 2. ชี้ไปที่ไฟล์ Zip ของเรา (ที่เราสร้างใน Step 3.3)
  #    (ข้างใน Zip นี้ 📦 ควรมีแค่ไฟล์ bootstrap ⚙️)
  filename = "lambda_function.zip"

  # 3. บอก Lambda ว่าเราจะใช้ "Custom Runtime" (แบบที่เราเตรียมมาเอง)
  #    - Runtime คือ "provided.al2" (สภาพแวดล้อม Amazon Linux 2)
  #    - Handler คือ "bootstrap" (ชื่อไฟล์ ⚙️ ที่เราคอมไพล์ไว้ ซึ่ง Lambda จะรัน)
  runtime = "provided.al2"
  handler = "bootstrap"

  # 4. ใช้ "บัตรอนุญาต" (Role) ที่เราสร้างในข้อ 3
  role = aws_iam_role.lambda_exec_role.arn

  # 5. (Best Practice) ติดตามการเปลี่ยนแปลงของไฟล์ Zip
  source_code_hash = filebase64sha256("lambda_function.zip")
}

# ------------------------------------------------------------------
# 7. สร้าง "นาฬิกาปลุก" ⏰ (EventBridge Rule)
# ------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "every_5_minutes" {
  name                = "every-5-minutes"
  description         = "Triggers the health checker every 5 minutes"
  
  # "ตั้งเวลาปลุก" ที่นี่! (คล้ายกับ cron job)
  schedule_expression = "rate(5 minutes)" 
}

# ------------------------------------------------------------------
# 8. ตั้งค่า "เป้าหมาย" (Target) ของนาฬิกาปลุก
# ------------------------------------------------------------------
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.every_5_minutes.name # 1. ใช้นาฬิกาปลุกจากข้อ 7
  arn  = aws_lambda_function.health_checker_func.arn  # 2. ให้ไปปลุก Lambda (ข้อ 6)
}

# ------------------------------------------------------------------
# 9. ให้ "สิทธิ์" 🪪 EventBridge ในการปลุก Lambda
# ------------------------------------------------------------------
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction" # 1. อนุญาตให้ "ปลุก" (Invoke)
  function_name = aws_lambda_function.health_checker_func.function_name # 2. ปลุก Lambda (ข้อ 6)
  principal     = "events.amazonaws.com" # 3. โดย "บริการ EventBridge"
  
  # 4. (สำคัญ) ระบุว่าให้ปลุกจาก "นาฬิกาปลุก" (ข้อ 7) เรือนนี้เท่านั้น
  source_arn = aws_cloudwatch_event_rule.every_5_minutes.arn
}

# ------------------------------------------------------------------
# 10. (ที่เพิ่งเพิ่ม!) "ติด" Policy สำหรับการเขียน Logs ✍️
# ------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "logs_attach" {
  role       = aws_iam_role.lambda_exec_role.name # 1. ติดให้กับ Role เดิม (ข้อ 3)
  
  # 2. นี่คือ "บัตรอนุญาต" สำเร็จรูปของ AWS
  #    ที่อนุญาตให้ Lambda สร้าง Log Group และ เขียน Log Events
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}