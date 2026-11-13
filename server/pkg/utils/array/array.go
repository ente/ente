package array

func UniqueInt64(input []int64) []int64 {
	visited := map[int64]bool{}
	var result []int64
	for _, value := range input {
		if !visited[value] {
			visited[value] = true
			result = append(result, value)
		}
	}
	return result
}

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
