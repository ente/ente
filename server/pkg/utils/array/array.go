package array

// UniqueInt64 returns unique elements in the input array
func UniqueInt64(input []int64) []int64 {
	visited := map[int64]bool{}
	var result []int64
	for _, value := range input {
		// check if already the mapped
		// variable is set to true or not
		if !visited[value] {
			visited[value] = true
			// Append to result slice.
			result = append(result, value)
		}
	}
	return result
}

// ContainsDuplicateInInt64Array returns true if the array contains duplicate elements.
func ContainsDuplicateInInt64Array(input []int64) bool {
	visited := map[int64]bool{}
	for _, value := range input {
		if visited[value] {
			return true
		}
		visited[value] = true
	}
	return false
}

// FindMissingElementsInSecondList identifies elements in 'sourceList' that are not present in 'targetList'.
// Returns:
//   - A slice of int64 representing the elements found in 'sourceList' but not in 'targetList'.
//     If all elements of 'sourceList' are present in 'targetList', an empty slice is returned.
//
// Example usage:
// missingElements := FindMissingElementsInSecondList([]int64{1, 2, 3, 4}, []int64{2, 4, 6})
// fmt.Println(missingElements) // Output: [1, 3]
func FindMissingElementsInSecondList(sourceList []int64, targetList []int64) []int64 {
	targetSet := make(map[int64]struct{})
	for _, item := range targetList {
		targetSet[item] = struct{}{}
	}

	var missingElements = make([]int64, 0)
	for _, item := range sourceList {
		if _, found := targetSet[item]; !found {
			missingElements = append(missingElements, item)
		}
	}

	return missingElements
}
