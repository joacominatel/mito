import MitoAssets
import MitoCore
import SwiftUI

/// The fixed item set: titled blocks of items, each added through a name search.
struct ItemSetEditor: View {
    @Bindable var model: OverridesModel
    @Binding var items: ItemSetDraft
    let gameData: GameData
    @State private var searchingBlock: ItemSetDraft.Block.ID?

    var body: some View {
        ForEach(items.blocks) { block in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField(
                        text: Binding(
                            get: { block.title }, set: { items.setTitle($0, of: block.id) }),
                        prompt: Text("Título del bloque", tableName: "Overrides")
                    ) {
                        Text("Título del bloque", tableName: "Overrides")
                    }
                    Button {
                        items.removeBlock(block.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Quitar bloque", tableName: "Overrides"))
                    .accessibilityLabel(Text("Quitar bloque", tableName: "Overrides"))
                }
                ForEach(block.items, id: \.id) { item in
                    ItemRow(
                        name: gameData.overridesName(of: item.id),
                        count: Binding(
                            get: { item.count },
                            set: { items.setCount($0, of: item.id, in: block.id) }),
                        remove: { items.setCount(0, of: item.id, in: block.id) })
                }
                Button {
                    model.itemQuery = ""
                    searchingBlock = block.id
                } label: {
                    Text("Agregar ítem…", tableName: "Overrides")
                }
                .buttonStyle(.link)
                .popover(
                    isPresented: Binding(
                        get: { searchingBlock == block.id },
                        set: { if !$0 { searchingBlock = nil } })
                ) {
                    ItemSearch(model: model, gameData: gameData) { item in
                        items.add(item, to: block.id)
                        searchingBlock = nil
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Button {
            items.addBlock(
                title: String(localized: "Bloque \(items.blocks.count + 1)", table: "Overrides"))
        } label: {
            Text("Agregar bloque", tableName: "Overrides")
        }
    }
}

private struct ItemRow: View {
    let name: String
    @Binding var count: Int
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Stepper(value: $count, in: 1...99) {
                Text("\(count.formatted())×", tableName: "Overrides")
                    .monospacedDigit()
            }
            .accessibilityLabel(Text("Cantidad de \(name)", tableName: "Overrides"))
            Button(action: remove) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(Text("Quitar ítem", tableName: "Overrides"))
            .accessibilityLabel(Text("Quitar \(name)", tableName: "Overrides"))
        }
    }
}

private struct ItemSearch: View {
    @Bindable var model: OverridesModel
    let gameData: GameData
    let pick: (ItemID) -> Void

    var body: some View {
        let results = model.itemResults(in: gameData)
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                text: $model.itemQuery, prompt: Text("Buscar ítem", tableName: "Overrides")
            ) {
                Text("Buscar ítem", tableName: "Overrides")
            }
            .textFieldStyle(.roundedBorder)
            if results.isEmpty {
                Group {
                    if model.itemQuery.isEmpty {
                        Text("Escribí parte del nombre.", tableName: "Overrides")
                    } else {
                        Text("Ningún ítem con ese nombre.", tableName: "Overrides")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results, id: \.id) { item in
                    Button {
                        pick(item.id)
                    } label: {
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(item.totalGold.formatted()) de oro", tableName: "Overrides")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 320, height: 300)
    }
}
