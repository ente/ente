export interface Comment {
    id: string;
    collectionID: number;
    fileID?: number;
    parentCommentID?: string;
    parentCommentUserID?: number;
    userID: number;
    anonUserID?: string;
    text: string;
    isDeleted: boolean;
    createdAt: number;
    updatedAt: number;
}

export interface UnifiedReaction {
    id: string;
    collectionID: number;
    fileID?: number;
    commentID?: string;
    isCommentReply?: boolean;
    reactionType: string;
    userID: number;
    anonUserID?: string;
    isDeleted: boolean;
    createdAt: number;
    updatedAt: number;
}
