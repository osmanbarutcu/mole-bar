import SwiftUI

/// Ayarlar sayfası. Menü çubuğu panelinde ve ana pencerede aynı görünür.
struct PanelSettingsPage: View {
    @ObservedObject var stats: StatsModel
    @StateObject private var loginItem = LoginItem()
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("weeklyScan") private var weeklyScan = false
    @AppStorage("displayMode") private var displayMode = "text"
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showRAM") private var showRAM = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("diskAlertEnabled") private var diskAlertEnabled = true
    @AppStorage("memoryAlertEnabled") private var memoryAlertEnabled = true
    @AppStorage("cpuAlertEnabled") private var cpuAlertEnabled = true
    @AppStorage("graphMetric") private var graphMetric = "cpu"
    @AppStorage("updateCheckEnabled") private var updateCheckEnabled = false
    @AppStorage(StatusItemController.defaultsKey) private var customStatusItem = false
    @AppStorage("diskAlertThreshold") private var diskAlertThreshold = 90
    @AppStorage("cacheAlertGB") private var cacheAlertGB = 0
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        ScrollView(showsIndicators: false) {
            GlassGroup(spacing: 12) {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "circle.lefthalf.filled", title: "Tema")
                        Picker("Tema", selection: $appearance) {
                            Text("Sistem").tag("system")
                            Text("Açık").tag("light")
                            Text("Koyu").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: appearance) { _, value in AppDelegate.applyAppearance(value) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "arrow.down.circle", title: "Güncellemeler", trailing: L("Sürüm %@", UpdateCheck.currentVersion))
                        Toggle("Yeni sürümü GitHub'dan denetle", isOn: $updateCheckEnabled)
                            .toggleStyle(RightSwitchStyle())
                            .controlSize(.small)
                            .onChange(of: updateCheckEnabled) { _, enabled in
                                if enabled { stats.checkForUpdateIfDue() }
                            }
                        if let update = stats.availableUpdate, updateCheckEnabled {
                            Text(L("Yeni sürüm var: %@", update.version)).font(.caption.weight(.semibold))
                            Button("Sürüm sayfasını aç") { NSWorkspace.shared.open(update.url) }
                                .glassButton()
                                .controlSize(.small)
                        }
                        Text("Kapalıdır. Açarsanız MoleBar günde en çok 1 kez api.github.com adresine istek gönderir. GitHub IP adresinizi görür. Veri gönderilmez, indirme yapılmaz.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "menubar.rectangle", title: "Menü çubuğu")
                        Picker("Görünüm", selection: $displayMode) {
                            Text("Metin").tag("text")
                            Text("İkon").tag("icon")
                            Text("Grafik").tag("graph")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Toggle("Özel menü çubuğu öğesi (deneysel)", isOn: $customStatusItem)
                            .toggleStyle(RightSwitchStyle())
                            .controlSize(.small)
                        Text("Açıkken ⌥⌘M menü çubuğu panelini açar ve kapatır. Kapalıyken kısayol ana pencereyi açar. Değişiklik için MoleBar'ı yeniden başlatın.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if displayMode == "graph" {
                            Picker("Grafik ölçümü", selection: $graphMetric) {
                                ForEach(GraphMetric.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "textformat.123", title: "Metin modunda göster")
                        Toggle("CPU", isOn: $showCPU)
                        Toggle("RAM", isOn: $showRAM)
                        Toggle("Disk", isOn: $showDisk)
                        Toggle("Etiketler", isOn: $showLabels)
                    }
                    .toggleStyle(RightSwitchStyle())
                    .controlSize(.small)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                    .disabled(displayMode != "text")
                    .opacity(displayMode == "text" ? 1 : 0.5)

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "power", title: "Başlatma ve kısayol")
                        Toggle("Girişte başlat", isOn: Binding(
                            get: { loginItem.isEnabled },
                            set: { loginItem.set($0) }
                        ))
                        if let error = loginItem.errorText {
                            Text(error).font(.caption2).foregroundStyle(.red)
                        }
                        Toggle("Kısayol ⌥⌘M ile ana pencereyi aç veya kapat", isOn: Binding(
                            get: { hotkeyEnabled },
                            set: { value in
                                hotkeyEnabled = value
                                if value { GlobalHotKey.register() } else { GlobalHotKey.unregister() }
                            }
                        ))
                        if hotkeyEnabled, let failure = GlobalHotKey.failureText(GlobalHotKey.lastStatus) {
                            Text(failure).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("Haftalık otomatik tarama", isOn: $weeklyScan)
                        Text("Tarama yalnızca önizlemedir ve sonucu bildirir. Mole önizlemesini, önbellek toplamını ve 90 günden eski proje çıktılarını ölçer. Hiçbir şey silmez. Uygulama açıkken çalışır.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(RightSwitchStyle())
                    .controlSize(.small)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "bell.badge", title: "Uyarılar")
                        Toggle("Disk eşiği aşılınca bildir", isOn: $diskAlertEnabled)
                            .toggleStyle(RightSwitchStyle())
                            .controlSize(.small)
                        Toggle("Bellek baskısı kritikken bildir", isOn: $memoryAlertEnabled)
                            .toggleStyle(RightSwitchStyle())
                            .controlSize(.small)
                        Toggle("Bir uygulama 5 dakika toplam %90 üstü CPU kullanırsa bildir", isOn: $cpuAlertEnabled)
                            .toggleStyle(RightSwitchStyle())
                            .controlSize(.small)
                        Stepper(L("Eşik: %%%ld", diskAlertThreshold), value: $diskAlertThreshold, in: 70...98)
                            .disabled(!diskAlertEnabled)
                            .controlSize(.small)
                            .font(.callout)
                        Stepper(cacheAlertGB == 0 ? L("Önbellek uyarısı: kapalı") : L("Önbellek uyarısı: %ld GB", cacheAlertGB), value: $cacheAlertGB, in: 0...50)
                            .controlSize(.small)
                            .font(.callout)
                        Text("Haftalık tarama önbellek toplamı eşiği aşarsa ayrı bildirim gönderir. 0 kapatır.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    FullDiskAccessCard()
                    MoveHistoryCard()
                    ErrorHistoryCard()
                }
                .padding(.vertical, 8)
            }
        }
        .shadowSafeScroll(vertical: 0) // İçerik zaten dikey padding(8) taşıyor.
    }
}
