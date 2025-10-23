package main

import (
	"context" // For AWS requests
	"fmt"
	"io"  // For reading entire file
	"log" // For logging errors
	"net/http"
	"strings"

	"github.com/aws/aws-lambda-go/lambda"     // For AWS Lambda
	"github.com/aws/aws-sdk-go-v2/aws"        // For AWS types
	"github.com/aws/aws-sdk-go-v2/config"     // For loading AWS credentials
	"github.com/aws/aws-sdk-go-v2/service/s3" // For talking to S3
)

// checkUrl ตรวจสอบ URL ที่กำหนด
// คืนค่า string บอกสถานะ ("OK", "Not OK")
// และคืนค่า error (ถ้ามีข้อผิดพลาดในการเชื่อมต่อ)
func checkUrl(url string) (string, error) {

	// 1. ยิง GET request
	resp, err := http.Get(url)

	// 2. ตรวจสอบข้อผิดพลาดในการเชื่อมต่อ
	if err != nil {
		return "", err // คืนค่าสตริงว่าง และ error ที่เกิดขึ้น
	}

	// 3. ปิด body เสมอเมื่อจบฟังก์ชัน
	defer resp.Body.Close()

	// 4. ตรวจสอบ StatusCode
	if resp.StatusCode == 200 {
		return "OK", nil // คืนค่า "OK" และ nil (ไม่มี error)
	}

	// 5. ถ้าไม่ใช่ 200
	return "Not OK", nil
}

func handleRequest() {
	fmt.Println("Starting website health check...")

	// 1. โหลด AWS Config
	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion("ap-southeast-1"),
	)
	if err != nil {
		log.Fatalf("Failed to load AWS config: %v", err)
	}

	// 2. สร้าง S3 client จาก config นั้น
	s3Client := s3.NewFromConfig(cfg)

	// 3. สร้าง input สำหรับดึงไฟล์จาก S3
	input := &s3.GetObjectInput{
		Bucket: aws.String("cloud-health-checker"),
		Key:    aws.String("urls.txt"),
	}

	// 4. เรียก GetObject เพื่อดึงไฟล์จาก S3
	result, err := s3Client.GetObject(context.TODO(), input)
	if err != nil {
		log.Fatalf("Failed to get object from S3: %v", err)
	}
	defer result.Body.Close()

	// 5. อ่านข้อมูลจากไฟล์ทั้งหมด
	data, err := io.ReadAll(result.Body)
	if err != nil {
		log.Fatalf("Failed to read S3 object: %v", err)
	}

	// 6. แปลงข้อมูลเป็น string
	fileContent := string(data)
	fmt.Printf("File content:\n%s\n", fileContent)

	// (เพิ่มบรรทัดนี้) ลบตัว \r (Windows carriage returns) ออกไปก่อน
	fileContent = strings.ReplaceAll(fileContent, "\r", "")

	// 7. หั่น string ก้อนนั้นให้เป็น []string โดยใช้ "\n" เป็นตัวคั่น
	urls := strings.Split(fileContent, "\n")

	// หรือถ้าต้องการอ่านทีละบรรทัด สามารถทำได้แบบนี้:
	/*
		scanner := bufio.NewScanner(bytes.NewReader(data))
		for scanner.Scan() {
			line := scanner.Text()
			fmt.Println("Line:", line)
		}
		if err := scanner.Err(); err != nil {
			log.Fatalf("Error scanning S3 object: %v", err)
		}
	*/

	// วนซ้ำ (loop) แต่ละ URL ใน list
	for _, url := range urls {

		// 1. เรียกใช้ฟังก์ชัน checkUrl ของเรา
		status, err := checkUrl(url)

		// 2. ตรวจสอบผลลัพธ์
		if err != nil {
			// กรณีนี้คือ 'err' จาก checkUrl (เช่น ต่อเน็ตไม่ได้, DNS พัง)
			fmt.Printf("Checking %s ... Error: %s\n", url, err.Error())
		} else {
			// กรณีนี้คือ 'status' จาก checkUrl (OK หรือ Not OK)
			fmt.Printf("Checking %s ... Status: %s\n", url, status)
		}
	}

	fmt.Println("Health check finished.")
}

func main() {
	// บอก Lambda ให้เริ่ม "รอฟัง"
	// และเมื่อถูกเรียก ให้ไปรันฟังก์ชัน handleRequest
	lambda.Start(handleRequest)
}
