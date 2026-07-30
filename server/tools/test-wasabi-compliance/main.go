package main

import (
	"flag"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"github.com/ente/museum/pkg/external/wasabi"
	"github.com/ente/museum/tools/pkg/cli"
)

const (
	bucket      = "ente-compliance-test"
	objectKey   = "compliance-test-object"
	objectValue = "test-object-contents"
)

func main() {
	// Can be overridden on the command line with `--endpoint-url`
	endpointURL := "https://s3.eu-central-2.wasabisys.com"

	onlyDelete := false
	flag.BoolVar(&onlyDelete, "only-delete", false,
		"If true, then we will only delete the object from the test bucket (sequence 2)")

	sess, err := cli.ParseAndCreateSession(endpointURL, false)
	if err != nil {
		return
	}

	s3Client := s3.New(sess)

	if !onlyDelete {
		err = sequence1(s3Client)
	} else {
		err = sequence2(s3Client)
	}
	if err != nil {
		return
	}

	fmt.Println("Checklist completed successfully")
}

// # Sequence 1
//
//   - Get and print the current compliance settings for the test Wasabi bucket.
//   - Update the compliance settings to set RetentionDays = 1.
//   - Get and verify the updated settings.
//   - Put an object into the bucket.
//   - Ensure it cannot be deleted or overwritten.
//   - Get and print the compliance settings for the test object in this bucket.
//   - Disable the conditional hold for the object.
//   - Ensure it still cannot be deleted (we'll need to wait for a day).
//   - Print and verify the updated compliance settings.
func sequence1(s3Client *s3.S3) error {
	_, err := getAndPrintBucketCompliance(s3Client)
	if err != nil {
		return err
	}

	err = enableBucketCompliance(s3Client)
	if err != nil {
		return err
	}

	err = verifyBucketComplianceEnabled(s3Client)
	if err != nil {
		return err
	}

	err = putObject(s3Client)
	if err != nil {
		return err
	}

	err = deleteObjectExpectingFailure(s3Client)
	if err != nil {
		return err
	}

	err = putObjectExpectingFailure(s3Client)
	if err != nil {
		return err
	}

	_, err = getAndPrintObjectCompliance(s3Client)
	if err != nil {
		return err
	}

	err = disableObjectConditionalHold(s3Client)
	if err != nil {
		return err
	}

	err = deleteObjectExpectingFailure(s3Client)
	if err != nil {
		return err
	}

	err = verifyExpectedObjectCompliance(s3Client)
	if err != nil {
		return err
	}

	return nil
}

// # Sequence 2
//
//   - Get and print the object's info.
//   - Delete the object. This time it should succeed.
func sequence2(s3Client *s3.S3) error {
	_, err := getAndPrintObjectCompliance(s3Client)
	if err != nil {
		return err
	}

	err = deleteObject(s3Client)
	if err != nil {
		return err
	}

	return nil
}

// Operations

func getAndPrintBucketCompliance(s3Client *s3.S3) (*wasabi.GetBucketComplianceOutput, error) {
	out, err := wasabi.GetBucketCompliance(s3Client, &wasabi.GetBucketComplianceInput{
		Bucket: aws.String(bucket),
	})
	if err != nil {
		fmt.Printf("GetBucketCompliance %s error: %s\n", bucket, err)
		return nil, err
	}

	fmt.Printf("GetBucketComplianceOutput: %v\n", out)
	return out, nil
}

func enableBucketCompliance(s3Client *s3.S3) error {
	out, err := wasabi.PutBucketCompliance(s3Client, &wasabi.PutBucketComplianceInput{
		Bucket: aws.String(bucket),
		BucketComplianceConfiguration: &wasabi.BucketComplianceConfiguration{
			Status:          aws.String(wasabi.BucketComplianceStatusEnabled),
			RetentionDays:   aws.Int64(1),
			ConditionalHold: aws.Bool(true),
		},
	})
	if err != nil {
		fmt.Printf("PutBucketCompliance %s error: %s\n", bucket, err)
		return err
	}

	fmt.Printf("PutBucketComplianceOutput: %v\n", out)
	return nil
}

func verifyBucketComplianceEnabled(s3Client *s3.S3) error {
	out, err := getAndPrintBucketCompliance(s3Client)
	if err != nil {
		return err
	}

	if *out.Status != wasabi.BucketComplianceStatusEnabled {
		err := fmt.Errorf("expected Status to be %q, got %q",
			string(wasabi.BucketComplianceStatusEnabled), *out.Status)
		fmt.Printf("Error: %s\n", err)
		return err
	}

	if *out.RetentionDays != 1 {
		err = fmt.Errorf("expected Status to be %d, got %d", 1, *out.RetentionDays)
		fmt.Printf("Error: %s\n", err)
		return err

	}

	if !*out.ConditionalHold {
		err = fmt.Errorf("expected ConditionalHold to be %t, got %t",
			true, *out.ConditionalHold)
		fmt.Printf("Error: %s\n", err)
		return err
	}

	return nil
}

func putObject(s3Client *s3.S3) error {
	uploader := s3manager.NewUploaderWithClient(s3Client)

	out, err := uploader.Upload(&s3manager.UploadInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
		Body:   aws.ReadSeekCloser(strings.NewReader(objectValue)),
	})
	if err != nil {
		fmt.Printf("Upload %s/%s error: %s\n", bucket, objectKey, err)
		return err
	}

	fmt.Printf("UploadOutput: %v\n", out)
	return nil
}

func putObjectExpectingFailure(s3Client *s3.S3) error {
	uploader := s3manager.NewUploaderWithClient(s3Client)

	out, err := uploader.Upload(&s3manager.UploadInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
		Body:   aws.ReadSeekCloser(strings.NewReader(objectValue)),
	})
	if err == nil {
		err = fmt.Errorf("expected Upload %s/%s to fail because of compliance being enabled, but it succeeded with output: %v",
			bucket, objectKey, out)
		fmt.Printf("Error: %s\n", err)
		return err
	}

	fmt.Printf("UploadError (expected): %v\n", err)
	return nil
}

func deleteObject(s3Client *s3.S3) error {
	out, err := s3Client.DeleteObject(&s3.DeleteObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
	})
	if err != nil {
		fmt.Printf("DeleteObject %s/%s error: %s\n", bucket, objectKey, err)
		return err
	}

	fmt.Printf("DeleteObjectOutput: %v\n", out)
	return nil
}

func deleteObjectExpectingFailure(s3Client *s3.S3) error {
	out, err := s3Client.DeleteObject(&s3.DeleteObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
	})
	if err == nil {
		err = fmt.Errorf("expected DeleteObject %s/%s to fail because of compliance being enabled, but it succeeded with output: %s",
			bucket, objectKey, out)
		fmt.Printf("Error: %s\n", err)
		return err
	}

	fmt.Printf("DeleteObjectError (expected): %v\n", err)
	return nil
}

func getAndPrintObjectCompliance(s3Client *s3.S3) (*wasabi.GetObjectComplianceOutput, error) {
	out, err := wasabi.GetObjectCompliance(s3Client, &wasabi.GetObjectComplianceInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
	})
	if err != nil {
		fmt.Printf("GetObjectCompliance %s error: %s\n", bucket, err)
		return nil, err
	}

	fmt.Printf("GetObjectComplianceOutput: %v\n", out)
	return out, nil
}

func disableObjectConditionalHold(s3Client *s3.S3) error {
	out, err := wasabi.PutObjectCompliance(s3Client, &wasabi.PutObjectComplianceInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
		ObjectComplianceConfiguration: &wasabi.ObjectComplianceConfiguration{
			ConditionalHold: aws.Bool(false),
		},
	})
	if err != nil {
		fmt.Printf("PutObjectCompliance %s error: %s\n", bucket, err)
		return err
	}

	fmt.Printf("PutObjectComplianceOutput: %v\n", out)
	return nil
}

func verifyExpectedObjectCompliance(s3Client *s3.S3) error {
	out, err := getAndPrintObjectCompliance(s3Client)
	if err != nil {
		return err
	}

	if *out.ConditionalHold {
		err = fmt.Errorf("expected ConditionalHold to be %t, got %t",
			false, *out.ConditionalHold)
		fmt.Printf("Error: %s\n", err)
		return err
	}

	return nil
}
