package main

import (
	"flag"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/tools/pkg/cli"
)

func main() {
	bucket := ""
	confirm := false

	flag.StringVar(&bucket, "bucket", "",
		"Bucket to delete from")

	flag.BoolVar(&confirm, "confirm", false,
		"By default, the tool does a dry run. Set this to true to do the actual abort")

	sess, err := cli.ParseAndCreateSession("", false)
	if err != nil {
		return
	}

	if bucket == "" {
		fmt.Printf("Error: no bucket specified (hint: use `--bucket`)\n")
		return
	}

	s3Client := s3.New(sess)

	// - List all multipart uploads
	// - Delete the ones that are older than x days (but only if `--confirm` is specified)

	listOut, err := s3Client.ListMultipartUploads(&s3.ListMultipartUploadsInput{
		Bucket: aws.String(bucket),
	})
	if err != nil {
		fmt.Printf("ListMultipartUploads %s error: %s\n", bucket, err)
		return
	}

	fmt.Printf("ListMultipartUploads: %v\n", listOut)

	if listOut.IsTruncated != nil && *listOut.IsTruncated {
		fmt.Printf("Warning: Found more than 1000 pending multipart uploads. We were not expecting this many.")
	}

	// 20 days ago
	cutoff := time.Now().AddDate(0, 0, -20)
	fmt.Printf("Cutoff: %v\n", cutoff)

	for _, upload := range listOut.Uploads {
		fmt.Printf("Processing multipart upload key %v id %v initiated %v\n",
			*upload.Key, *upload.UploadId, *upload.Initiated)
		if upload.Initiated.After(cutoff) {
			fmt.Printf("Skipping multipart upload since it was initated (%v) after cutoff (%v)\n",
				*upload.Initiated, cutoff)
			continue
		}

		if confirm {
			abortMultipartUpload(s3Client, bucket, *upload.Key, *upload.UploadId)
		} else {
			fmt.Printf("Dry run: AbortMultipartUpload: %v/%v/%v\n", bucket,
				*upload.Key,
				*upload.UploadId)
		}
	}
}

func abortMultipartUpload(s3Client *s3.S3, bucket string, key string, uploadId string) error {
	_, err := s3Client.AbortMultipartUpload(&s3.AbortMultipartUploadInput{
		Bucket:   &bucket,
		Key:      &key,
		UploadId: &uploadId,
	})
	if err != nil {
		fmt.Printf("AbortMultipartUpload failed: key %v id %v: %v\n", key, uploadId, err)
		return err
	}

	fmt.Printf("AbortMultipartUpload success key %v id %v\n",
		key, uploadId)
	return nil
}
