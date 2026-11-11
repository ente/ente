struct DeviceFolderTransferPlan {
    let missingIDs: Set<String>
    let addedIDs: Set<String>
    let removedIDs: Set<String>
    let completedIDs: Set<String>

    init(
        requestedIDs: Set<String>,
        accessibleIDs: Set<String>,
        sourceMemberIDs: Set<String>?,
        targetMemberIDs: Set<String>
    ) {
        completedIDs = requestedIDs
            .intersection(accessibleIDs)
            .intersection(sourceMemberIDs ?? requestedIDs)
        missingIDs = requestedIDs.subtracting(completedIDs)
        addedIDs = completedIDs.subtracting(targetMemberIDs)
        removedIDs = sourceMemberIDs == nil ? [] : completedIDs
    }
}
