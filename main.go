package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// checkUrl ตรวจสอบ URL ที่กำหนดด้วย HTTP Client ที่มี Timeout
func checkUrl(url string) (string, error) {

	// 1. สร้าง http.Client ที่มีการกำหนด Timeout ชัดเจน
	var netClient = &http.Client{
		Timeout: 10 * time.Second, // กำหนดให้รอสูงสุด 10 วินาที
	}

	// 2. ยิง GET request
	resp, err := netClient.Get(url)

	// 3. ตรวจสอบข้อผิดพลาดในการเชื่อมต่อ
	if err != nil {
		return "", err
	}

	// 4. ปิด body เสมอ
	defer resp.Body.Close()

	// 5. ตรวจสอบ StatusCode
	if resp.StatusCode == 200 {
		return "OK", nil
	}

	// 6. ถ้าไม่ใช่ 200
	return "Not OK", nil
}

// Handler หลักของ Lambda (รับ Context และคืนค่า error)
func handleRequest(ctx context.Context) error {
	fmt.Println("Starting website health check...")

	// 1. โหลด AWS Config (ใช้ Context ที่รับมา)
	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion("ap-southeast-1"),
	)
	if err != nil {
		log.Printf("ERROR: Failed to load AWS config: %v", err)
		return fmt.Errorf("failed to load AWS config: %w", err)
	}

	// 2. สร้าง S3 client
	s3Client := s3.NewFromConfig(cfg)

	// 3. สร้าง input สำหรับ S3
	input := &s3.GetObjectInput{
		Bucket: aws.String("cloud-health-checker"),
		Key:    aws.String("urls.txt"),
	}

	// 4. เรียก GetObject (ใช้ Context ที่รับมา)
	result, err := s3Client.GetObject(ctx, input)
	if err != nil {
		log.Printf("ERROR: Failed to get object from S3: %v", err)
		return fmt.Errorf("failed to get object from S3: %w", err)
	}
	defer result.Body.Close()

	// 5. อ่านข้อมูลจากไฟล์
	data, err := io.ReadAll(result.Body)
	if err != nil {
		log.Printf("ERROR: Failed to read S3 object: %v", err)
		return fmt.Errorf("failed to read S3 object: %w", err)
	}

	// 6. เตรียม URL list (ลบ \r และหั่นตาม \n)
	fileContent := string(data)
	fileContent = strings.ReplaceAll(fileContent, "\r", "")
	urls := strings.Split(fileContent, "\n")

	// 7. วนซ้ำ (loop) ตรวจสอบแต่ละ URL
	for _, url := range urls {

		// 8. ลบช่องว่างและข้ามบรรทัดว่างเปล่า
		url = strings.TrimSpace(url)
		if url == "" {
			fmt.Println("Skipping empty line.")
			continue
		}

		// 9. ตรวจสอบ URL
		status, err := checkUrl(url)

		// 10. บันทึกผลลัพธ์
		if err != nil {
			fmt.Printf("Checking %s ... Error: %s\n", url, err.Error())
		} else {
			fmt.Printf("Checking %s ... Status: %s\n", url, status)
		}
	}

	fmt.Println("Health check finished.")
	return nil
}

func main() {
	// บอก Lambda ให้เริ่ม "รอฟัง" handler ที่มี Context
	lambda.Start(handleRequest)
}
