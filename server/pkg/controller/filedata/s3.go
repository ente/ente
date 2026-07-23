package filedata

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"github.com/ente/museum/ente"
	fileData "github.com/ente/museum/ente/filedata"
	"github.com/ente/museum/pkg/utils/file"
	"github.com/ente/stacktrace"
	log "github.com/sirupsen/logrus"
	"io"
	"os"
	"strings"
	stime "time"
)

const PreSignedRequestValidityDuration = 7 * 24 * stime.Hour

func (c *Controller) getUploadURL(dc string, objectKey string) (*ente.UploadURL, error) {
	s3Client := c.S3Config.GetS3Client(dc)
	r, _ := s3Client.PutObjectRequest(&s3.PutObjectInput{
		Bucket: c.S3Config.GetBucket(dc),
		Key:    &objectKey,
	})
	url, err := r.Presign(PreSignedRequestValidityDuration)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	err = c.ObjectCleanupController.AddTempObjectKey(objectKey, dc)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &ente.UploadURL{
		ObjectKey: objectKey,
		URL:       url,
	}, nil
}
func (c *Controller) getMultiPartUploadURL(dc string, objectKey string, count *int64) (*ente.MultipartUploadURLs, error) {
	s3Client := c.S3Config.GetS3Client(dc)
	bucket := c.S3Config.GetBucket(dc)
	r, err := s3Client.CreateMultipartUpload(&s3.CreateMultipartUploadInput{
		Bucket: bucket,
		Key:    &objectKey,
	})
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	err = c.ObjectCleanupController.AddMultipartTempObjectKey(objectKey, *r.UploadId, dc)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	multipartUploadURLs := ente.MultipartUploadURLs{ObjectKey: objectKey}
	urls := make([]string, 0)
	for i := int64(1); i <= *count; i++ {
		partReq, _ := s3Client.UploadPartRequest(&s3.UploadPartInput{
			Bucket:     bucket,
			Key:        &objectKey,
			UploadId:   r.UploadId,
			PartNumber: &i,
		})
		partUrl, partUrlErr := partReq.Presign(PreSignedRequestValidityDuration)
		if partUrlErr != nil {
			return nil, stacktrace.Propagate(partUrlErr, "")
		}
		urls = append(urls, partUrl)
	}
	multipartUploadURLs.PartURLs = urls
	r2, _ := s3Client.CompleteMultipartUploadRequest(&s3.CompleteMultipartUploadInput{
		Bucket:   bucket,
		Key:      &objectKey,
		UploadId: r.UploadId,
	})
	url, err := r2.Presign(PreSignedRequestValidityDuration)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	multipartUploadURLs.CompleteURL = url
	return &multipartUploadURLs, nil
}

func (c *Controller) signedUrlGet(dc string, objectKey string) (*ente.UploadURL, error) {
	s3Client := c.S3Config.GetS3Client(dc)
	input := &s3.GetObjectInput{
		Bucket: c.S3Config.GetBucket(dc),
		Key:    &objectKey,
	}
	input.ResponseContentDisposition = aws.String("attachment")
	r, _ := s3Client.GetObjectRequest(input)
	url, err := r.Presign(PreSignedRequestValidityDuration)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &ente.UploadURL{ObjectKey: objectKey, URL: url}, nil
}

func (c *Controller) downloadObject(ctx context.Context, objectKey string, dc string) (fileData.S3FileMetadata, error) {
	var obj fileData.S3FileMetadata
	buff := &aws.WriteAtBuffer{}
	bucket := c.S3Config.GetBucket(dc)
	downloader := c.downloadManagerCache[dc]
	_, err := downloader.DownloadWithContext(ctx, buff, &s3.GetObjectInput{
		Bucket: bucket,
		Key:    &objectKey,
	})
	if err != nil {
		return obj, err
	}
	err = json.Unmarshal(buff.Bytes(), &obj)
	if err != nil {
		return obj, stacktrace.Propagate(err, "unmarshal failed")
	}
	return obj, nil
}

// uploadObject uploads the embedding object to the object store and returns the object size
func (c *Controller) uploadObject(obj fileData.S3FileMetadata, objectKey string, dc string) (int64, error) {
	embeddingObj, _ := json.Marshal(obj)
	s3Client := c.S3Config.GetS3Client(dc)
	s3Bucket := c.S3Config.GetBucket(dc)
	uploader := s3manager.NewUploaderWithClient(&s3Client)
	up := s3manager.UploadInput{
		Bucket: s3Bucket,
		Key:    &objectKey,
		Body:   bytes.NewReader(embeddingObj),
	}
	var err error
	var result *s3manager.UploadOutput
	for range 3 {
		result, err = uploader.Upload(&up)
		if err == nil || !strings.Contains(err.Error(), "connection reset by peer") {
			break
		}
		stime.Sleep(50 * stime.Millisecond)
	}
	if err != nil {
		log.Error(err)
		return -1, stacktrace.Propagate(err, "metadata upload failed")
	}
	log.Infof("Uploaded to bucket %s", result.Location)
	return int64(len(embeddingObj)), nil
}

func (c *Controller) verifySize(bucketID string, objectKey string, expectedSize int64) error {
	s3Client := c.S3Config.GetS3Client(bucketID)
	bucket := c.S3Config.GetBucket(bucketID)
	res, err := s3Client.HeadObject(&s3.HeadObjectInput{
		Bucket: bucket,
		Key:    &objectKey,
	})
	if err != nil {
		return stacktrace.Propagate(err, "Fetching object info from bucket %s failed", *bucket)
	}

	if *res.ContentLength != expectedSize {
		err = fmt.Errorf("size of the uploaded file (%d) does not match the expected size (%d) in bucket %s",
			*res.ContentLength, expectedSize, *bucket)
		//c.notifyDiscord(fmt.Sprint(err))
		return stacktrace.Propagate(err, "")
	}
	return nil
}

type ReplicateObjectReq struct {
	ObjectKey    string
	SrcBucketID  string
	DestBucketID string
	ObjectSize   int64
}

// copyObject copies the object from srcObjectKey to destObjectKey in the same bucket and returns the object size
func (c *Controller) replicateObject(ctx context.Context, req *ReplicateObjectReq) error {
	if err := file.EnsureSufficientSpace(req.ObjectSize); err != nil {
		return stacktrace.Propagate(err, "")
	}
	filePath, file, err := file.CreateTemporaryFile(c.tempStorage, req.ObjectKey)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to create temporary file")
	}
	defer os.Remove(filePath)
	defer file.Close()
	//s3Client := c.S3Config.GetS3Client(req.SrcBucketID)
	bucket := c.S3Config.GetBucket(req.SrcBucketID)
	downloader := c.downloadManagerCache[req.SrcBucketID]
	_, err = downloader.DownloadWithContext(ctx, file, &s3.GetObjectInput{
		Bucket: bucket,
		Key:    &req.ObjectKey,
	})
	if err != nil {
		return stacktrace.Propagate(err, "Failed to download object from bucket %s", req.SrcBucketID)
	}
	if err := c.verifySize(req.SrcBucketID, req.ObjectKey, req.ObjectSize); err != nil {
		return stacktrace.Propagate(err, "")
	}
	dstClient := c.S3Config.GetS3Client(req.DestBucketID)
	uploader := s3manager.NewUploaderWithClient(&dstClient)
	file.Seek(0, io.SeekStart)
	up := s3manager.UploadInput{
		Bucket: c.S3Config.GetBucket(req.DestBucketID),
		Key:    aws.String(req.ObjectKey),
		Body:   file,
	}
	result, err := uploader.Upload(&up)
	if err != nil {
		return stacktrace.Propagate(err, "Failed to upload object to bucket %s", req.DestBucketID)
	}
	log.Infof("Uploaded to bucket %s", result.Location)
	// verify the size of the uploaded object
	if err := c.verifySize(req.DestBucketID, req.ObjectKey, req.ObjectSize); err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}
