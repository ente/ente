import { getKV, setKV } from "ente-base/kv";
import { z } from "zod";

const ClusterIDsByCGroupID = z.record(z.string(), z.array(z.string()));

export type ClusterIDsByCGroupID = z.infer<typeof ClusterIDsByCGroupID>;

// Keep this in KV to avoid an IndexedDB migration.
const savedRejectedClusters = async (): Promise<ClusterIDsByCGroupID> =>
    ClusterIDsByCGroupID.parse((await getKV("rejectedClusters")) ?? {});

const saveRejectedClusters = (entries: ClusterIDsByCGroupID) =>
    setKV("rejectedClusters", entries);

export const savedRejectedClustersForCGroup = async (
    cgroupID: string,
): Promise<string[]> =>
    savedRejectedClusters().then((cs) => cs[cgroupID] ?? []);

export const saveRejectedClustersForCGroup = async (
    cgroupID: string,
    clusterIDs: string[],
) => {
    const rejectedClusters = await savedRejectedClusters();
    rejectedClusters[cgroupID] = clusterIDs;
    return saveRejectedClusters(rejectedClusters);
};
