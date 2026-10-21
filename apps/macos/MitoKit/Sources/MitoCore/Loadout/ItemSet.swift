public struct ItemSet: Hashable, Sendable {
    public struct Block: Hashable, Sendable {
        public struct Item: Hashable, Sendable {
            public let id: ItemID
            public let count: Int

            public init(id: ItemID, count: Int = 1) {
                self.id = id
                self.count = count
            }
        }

        /// Shown by the client as the block heading, so it carries the explanation text.
        public let title: String
        public let items: [Item]

        public init(title: String, items: [Item]) {
            self.title = title
            self.items = items
        }
    }

    public let blocks: [Block]

    public init(blocks: [Block]) {
        self.blocks = blocks
    }
}
