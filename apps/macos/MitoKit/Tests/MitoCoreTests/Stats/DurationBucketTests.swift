import MitoCore
import Testing

struct DurationBucketTests {
    @Test func mapsTheSnapshotBuckets() {
        #expect(
            DurationBucket.allCases.map(\.rawValue) == [
                "<20", "20-25", "25-30", "30-35", "35-40", "40+",
            ])
    }

    /// §18.4 splits early at 25 minutes and late at 35, so the bounds must tile without gaps.
    @Test func bucketsTileGameLengthWithoutGapsOrOverlaps() {
        let buckets = DurationBucket.allCases
        #expect(buckets.first?.lowerMinutes == 0)
        #expect(buckets.last?.upperMinutes == nil)
        for (bucket, next) in zip(buckets, buckets.dropFirst()) {
            #expect(bucket.upperMinutes == next.lowerMinutes)
        }
    }

    @Test func aBucketOutsideTheEncodingIsNotABucket() {
        #expect(DurationBucket(rawValue: "45+") == nil)
    }
}
