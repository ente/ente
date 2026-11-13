// These operations follow AWS SDK v1 service templates with Wasabi-specific
// payloads. Wasabi compliance and S3 Object Lock are mutually exclusive.
package wasabi

import (
	"github.com/aws/aws-sdk-go/aws/awsutil"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/service/s3"
)

func newRequest(c *s3.S3, op *request.Operation, params, data interface{}) *request.Request {
	req := c.NewRequest(op, params, data)
	return req
}

const opGetBucketCompliance = "GetBucketCompliance"

func GetBucketCompliance(c *s3.S3, input *GetBucketComplianceInput) (*GetBucketComplianceOutput, error) {
	req, out := GetBucketComplianceRequest(c, input)
	return out, req.Send()
}

func GetBucketComplianceRequest(c *s3.S3, input *GetBucketComplianceInput) (req *request.Request, output *GetBucketComplianceOutput) {
	op := &request.Operation{
		Name:       opGetBucketCompliance,
		HTTPMethod: "GET",
		HTTPPath:   "/{Bucket}?compliance",
	}

	if input == nil {
		input = &GetBucketComplianceInput{}
	}

	output = &GetBucketComplianceOutput{}
	req = newRequest(c, op, input, output)
	return
}

type GetBucketComplianceInput struct {
	_ struct{} `locationName:"GetBucketComplianceRequest" type:"structure"`

	Bucket *string `location:"uri" locationName:"Bucket" type:"string" required:"true"`
}

func (s GetBucketComplianceInput) String() string {
	return awsutil.Prettify(s)
}

func (s GetBucketComplianceInput) GoString() string {
	return s.String()
}

func (s *GetBucketComplianceInput) Validate() error {
	invalidParams := request.ErrInvalidParams{Context: "GetBucketComplianceInput"}
	if s.Bucket == nil {
		invalidParams.Add(request.NewErrParamRequired("Bucket"))
	}
	if s.Bucket != nil && len(*s.Bucket) < 1 {
		invalidParams.Add(request.NewErrParamMinLen("Bucket", 1))
	}

	if invalidParams.Len() > 0 {
		return invalidParams
	}
	return nil
}

func (s *GetBucketComplianceInput) SetBucket(v string) *GetBucketComplianceInput {
	s.Bucket = &v
	return s
}

type GetBucketComplianceOutput struct {
	_ struct{} `type:"structure"`

	Status *string `type:"string" enum:"BucketComplianceStatus"`

	LockTime *string `type:"string"`

	RetentionDays *int64 `type:"integer"`

	ConditionalHold *bool `type:"boolean"`

	DeleteAfterRetention *bool `type:"boolean"`
}

func (s GetBucketComplianceOutput) String() string {
	return awsutil.Prettify(s)
}

func (s GetBucketComplianceOutput) GoString() string {
	return s.String()
}

func (s *GetBucketComplianceOutput) SetStatus(v string) *GetBucketComplianceOutput {
	s.Status = &v
	return s
}

func (s *GetBucketComplianceOutput) SetLockTime(v string) *GetBucketComplianceOutput {
	s.LockTime = &v
	return s
}

func (s *GetBucketComplianceOutput) SetRetentionDays(v int64) *GetBucketComplianceOutput {
	s.RetentionDays = &v
	return s
}

func (s *GetBucketComplianceOutput) SetConditionalHold(v bool) *GetBucketComplianceOutput {
	s.ConditionalHold = &v
	return s
}

func (s *GetBucketComplianceOutput) SetDeleteAfterRetention(v bool) *GetBucketComplianceOutput {
	s.DeleteAfterRetention = &v
	return s
}

const (
	BucketComplianceStatusEnabled = "enabled"

	BucketComplianceStatusDisabled = "disabled"
)

func BucketComplianceStatus_Values() []string {
	return []string{
		BucketComplianceStatusEnabled,
		BucketComplianceStatusDisabled,
	}
}

const opPutBucketCompliance = "PutBucketCompliance"

func PutBucketCompliance(c *s3.S3, input *PutBucketComplianceInput) (*PutBucketComplianceOutput, error) {
	req, out := PutBucketComplianceRequest(c, input)
	return out, req.Send()
}

func PutBucketComplianceRequest(c *s3.S3, input *PutBucketComplianceInput) (req *request.Request, output *PutBucketComplianceOutput) {
	op := &request.Operation{
		Name:       opPutBucketCompliance,
		HTTPMethod: "PUT",
		HTTPPath:   "/{Bucket}?compliance",
	}

	if input == nil {
		input = &PutBucketComplianceInput{}
	}

	output = &PutBucketComplianceOutput{}
	req = newRequest(c, op, input, output)
	return
}

type PutBucketComplianceInput struct {
	_ struct{} `locationName:"PutBucketComplianceRequest" type:"structure" payload:"BucketComplianceConfiguration"`

	Bucket *string `location:"uri" locationName:"Bucket" type:"string" required:"true"`

	BucketComplianceConfiguration *BucketComplianceConfiguration `locationName:"BucketComplianceConfiguration" type:"structure" required:"true"`
}

type BucketComplianceConfiguration struct {
	_ struct{} `type:"structure"`

	// Enabling compliance applies it immediately to every object in the bucket.
	Status *string `type:"string" enum:"BucketComplianceStatus"`

	// "now" locks immediately, "off" leaves settings unlocked, and an ISO time
	// schedules the lock. Once locked, settings cannot be reduced without Wasabi
	// support.
	LockTime *string `type:"string"`

	// Required minimum retention after creation or release from conditional hold.
	// Per-object retention may be extended, but not shortened.
	RetentionDays *int64 `type:"integer"`

	// Places new objects on hold. Defaults to false and may be changed after the
	// settings are locked.
	ConditionalHold *bool `type:"boolean"`

	// Defaults to false and may be changed after the settings are locked.
	DeleteAfterRetention *bool `type:"boolean"`
}

func (s PutBucketComplianceInput) String() string {
	return awsutil.Prettify(s)
}

func (s PutBucketComplianceInput) GoString() string {
	return s.String()
}

func (s *PutBucketComplianceInput) Validate() error {
	invalidParams := request.ErrInvalidParams{Context: "PutBucketComplianceInput"}
	if s.Bucket == nil {
		invalidParams.Add(request.NewErrParamRequired("Bucket"))
	}
	if s.Bucket != nil && len(*s.Bucket) < 1 {
		invalidParams.Add(request.NewErrParamMinLen("Bucket", 1))
	}
	if s.BucketComplianceConfiguration == nil {
		invalidParams.Add(request.NewErrParamRequired("BucketComplianceConfiguration"))
	}
	if s.BucketComplianceConfiguration != nil {
		if err := s.BucketComplianceConfiguration.Validate(); err != nil {
			invalidParams.AddNested("BucketComplianceConfiguration", err.(request.ErrInvalidParams))
		}
	}

	if invalidParams.Len() > 0 {
		return invalidParams
	}
	return nil
}

func (s *PutBucketComplianceInput) SetBucket(v string) *PutBucketComplianceInput {
	s.Bucket = &v
	return s
}

func (s *PutBucketComplianceInput) SetBucketComplianceConfiguration(v BucketComplianceConfiguration) *PutBucketComplianceInput {
	s.BucketComplianceConfiguration = &v
	return s
}

func (s BucketComplianceConfiguration) String() string {
	return awsutil.Prettify(s)
}

func (s BucketComplianceConfiguration) GoString() string {
	return s.String()
}

func (s *BucketComplianceConfiguration) Validate() error {
	invalidParams := request.ErrInvalidParams{Context: "BucketComplianceConfiguration"}
	if s.RetentionDays == nil {
		invalidParams.Add(request.NewErrParamRequired("RetentionDays"))
	}

	if invalidParams.Len() > 0 {
		return invalidParams
	}
	return nil
}

func (s *BucketComplianceConfiguration) SetStatus(v string) *BucketComplianceConfiguration {
	s.Status = &v
	return s
}

func (s *BucketComplianceConfiguration) SetLockTime(v string) *BucketComplianceConfiguration {
	s.LockTime = &v
	return s
}

func (s *BucketComplianceConfiguration) SetRetentionDays(v int64) *BucketComplianceConfiguration {
	s.RetentionDays = &v
	return s
}

func (s *BucketComplianceConfiguration) SetConditionalHold(v bool) *BucketComplianceConfiguration {
	s.ConditionalHold = &v
	return s
}

func (s *BucketComplianceConfiguration) SetDeleteAfterRetention(v bool) *BucketComplianceConfiguration {
	s.DeleteAfterRetention = &v
	return s
}

type PutBucketComplianceOutput struct {
	_ struct{} `type:"structure"`
}

func (s PutBucketComplianceOutput) String() string {
	return awsutil.Prettify(s)
}

func (s PutBucketComplianceOutput) GoString() string {
	return s.String()
}

const opGetObjectCompliance = "GetObjectCompliance"

func GetObjectCompliance(c *s3.S3, input *GetObjectComplianceInput) (*GetObjectComplianceOutput, error) {
	req, out := GetObjectComplianceRequest(c, input)
	return out, req.Send()
}

func GetObjectComplianceRequest(c *s3.S3, input *GetObjectComplianceInput) (req *request.Request, output *GetObjectComplianceOutput) {
	op := &request.Operation{
		Name:       opGetObjectCompliance,
		HTTPMethod: "GET",
		HTTPPath:   "/{Bucket}/{Key+}?compliance",
	}

	if input == nil {
		input = &GetObjectComplianceInput{}
	}

	output = &GetObjectComplianceOutput{}
	req = newRequest(c, op, input, output)
	return
}

type GetObjectComplianceInput struct {
	_ struct{} `locationName:"GetObjectComplianceRequest" type:"structure"`

	Bucket *string `location:"uri" locationName:"Bucket" type:"string" required:"true"`

	Key *string `location:"uri" locationName:"Key" min:"1" type:"string" required:"true"`
}

func (s GetObjectComplianceInput) String() string {
	return awsutil.Prettify(s)
}

func (s GetObjectComplianceInput) GoString() string {
	return s.String()
}

func (s *GetObjectComplianceInput) Validate() error {
	invalidParams := request.ErrInvalidParams{Context: "GetObjectComplianceInput"}
	if s.Bucket == nil {
		invalidParams.Add(request.NewErrParamRequired("Bucket"))
	}
	if s.Bucket != nil && len(*s.Bucket) < 1 {
		invalidParams.Add(request.NewErrParamMinLen("Bucket", 1))
	}
	if s.Key == nil {
		invalidParams.Add(request.NewErrParamRequired("Key"))
	}
	if s.Key != nil && len(*s.Key) < 1 {
		invalidParams.Add(request.NewErrParamMinLen("Key", 1))
	}

	if invalidParams.Len() > 0 {
		return invalidParams
	}
	return nil
}

func (s *GetObjectComplianceInput) SetBucket(v string) *GetObjectComplianceInput {
	s.Bucket = &v
	return s
}

func (s *GetObjectComplianceInput) SetKey(v string) *GetObjectComplianceInput {
	s.Key = &v
	return s
}

type GetObjectComplianceOutput struct {
	_ struct{} `type:"structure"`

	RetentionTime *string `type:"string"`

	ConditionalHold *bool `type:"boolean"`

	LegalHold *bool `type:"boolean"`

	SHA256 *string `type:"string"`
}

func (s GetObjectComplianceOutput) String() string {
	return awsutil.Prettify(s)
}

func (s GetObjectComplianceOutput) GoString() string {
	return s.String()
}

func (s *GetObjectComplianceOutput) SetRetentionTime(v string) *GetObjectComplianceOutput {
	s.RetentionTime = &v
	return s
}

func (s *GetObjectComplianceOutput) SetConditionalHold(v bool) *GetObjectComplianceOutput {
	s.ConditionalHold = &v
	return s
}

func (s *GetObjectComplianceOutput) SetLegalHold(v bool) *GetObjectComplianceOutput {
	s.LegalHold = &v
	return s
}

func (s *GetObjectComplianceOutput) SetSHA256(v string) *GetObjectComplianceOutput {
	s.SHA256 = &v
	return s
}

const opPutObjectCompliance = "PutObjectCompliance"

func PutObjectCompliance(c *s3.S3, input *PutObjectComplianceInput) (*PutObjectComplianceOutput, error) {
	req, out := PutObjectComplianceRequest(c, input)
	return out, req.Send()
}

func PutObjectComplianceRequest(c *s3.S3, input *PutObjectComplianceInput) (req *request.Request, output *PutObjectComplianceOutput) {
	op := &request.Operation{
		Name:       opPutObjectCompliance,
		HTTPMethod: "PUT",
		HTTPPath:   "/{Bucket}/{Key+}?compliance",
	}

	if input == nil {
		input = &PutObjectComplianceInput{}
	}

	output = &PutObjectComplianceOutput{}
	req = newRequest(c, op, input, output)
	return
}

type PutObjectComplianceInput struct {
	_ struct{} `locationName:"PutObjectComplianceRequest" type:"structure" payload:"ObjectComplianceConfiguration"`

	Bucket *string `location:"uri" locationName:"Bucket" type:"string" required:"true"`

	Key *string `location:"uri" locationName:"Key" min:"1" type:"string" required:"true"`

	ObjectComplianceConfiguration *ObjectComplianceConfiguration `locationName:"ObjectComplianceConfiguration" type:"structure" required:"true"`
}

type ObjectComplianceConfiguration struct {
	_ struct{} `type:"structure"`

	// Must be later than the retention required by the bucket policy.
	RetentionTime *string `type:"string"`

	// Setting this to false releases the hold, starts the retention period, and
	// cannot be reversed.
	ConditionalHold *bool `type:"boolean"`

	// A legal hold prevents deletion regardless of the retention period.
	LegalHold *bool `type:"boolean"`
}

func (s PutObjectComplianceInput) String() string {
	return awsutil.Prettify(s)
}

func (s PutObjectComplianceInput) GoString() string {
	return s.String()
}

func (s *PutObjectComplianceInput) Validate() error {
	invalidParams := request.ErrInvalidParams{Context: "PutObjectComplianceInput"}
	if s.Bucket == nil {
		invalidParams.Add(request.NewErrParamRequired("Bucket"))
	}
	if s.Bucket != nil && len(*s.Bucket) < 1 {
		invalidParams.Add(request.NewErrParamMinLen("Bucket", 1))
	}
	if s.Key == nil {
		invalidParams.Add(request.NewErrParamRequired("Key"))
	}
	if s.Key != nil && len(*s.Key) < 1 {
		invalidParams.Add(request.NewErrParamMinLen("Key", 1))
	}
	if s.ObjectComplianceConfiguration == nil {
		invalidParams.Add(request.NewErrParamRequired("ObjectComplianceConfiguration"))
	}
	if s.ObjectComplianceConfiguration != nil {
		if err := s.ObjectComplianceConfiguration.Validate(); err != nil {
			invalidParams.AddNested("ObjectComplianceConfiguration", err.(request.ErrInvalidParams))
		}
	}

	if invalidParams.Len() > 0 {
		return invalidParams
	}
	return nil
}

func (s *PutObjectComplianceInput) SetBucket(v string) *PutObjectComplianceInput {
	s.Bucket = &v
	return s
}

func (s *PutObjectComplianceInput) SetKey(v string) *PutObjectComplianceInput {
	s.Key = &v
	return s
}

func (s ObjectComplianceConfiguration) String() string {
	return awsutil.Prettify(s)
}

func (s ObjectComplianceConfiguration) GoString() string {
	return s.String()
}

func (s *ObjectComplianceConfiguration) Validate() error {
	return nil
}

func (s *ObjectComplianceConfiguration) SetRetentionTime(v string) *ObjectComplianceConfiguration {
	s.RetentionTime = &v
	return s
}

func (s *ObjectComplianceConfiguration) SetConditionalHold(v bool) *ObjectComplianceConfiguration {
	s.ConditionalHold = &v
	return s
}

func (s *ObjectComplianceConfiguration) SetLegalHold(v bool) *ObjectComplianceConfiguration {
	s.LegalHold = &v
	return s
}

type PutObjectComplianceOutput struct {
	_ struct{} `type:"structure"`
}

func (s PutObjectComplianceOutput) String() string {
	return awsutil.Prettify(s)
}

func (s PutObjectComplianceOutput) GoString() string {
	return s.String()
}
