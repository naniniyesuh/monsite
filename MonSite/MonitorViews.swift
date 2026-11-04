import SwiftUI
import UIKit
import Charts

// MARK: - İzleme listesi

struct MonitorsView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if store.monitors.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 64, height: 64)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text("Sitelerinizi düzenli izleyin").font(.headline)
                            Text("Seçtiğiniz sıklıkta otomatik kontrol yapılır ve her sonuç bir öncekiyle karşılaştırılır.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showAdd = true
                            } label: {
                                Label("İzleme ekle", systemImage: "plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding(.vertical, 12)
                    }
                } else {
                    Section {
                        ForEach(store.monitors) { m in
                            NavigationLink {
                                MonitorDetailView(monitorID: m.id)
                            } label: {
                                MonitorRow(monitor: m, running: store.runningID == m.id, queued: store.queue.contains(m.id))
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.runNow(m.id)
                                } label: {
                                    Label("Şimdi", systemImage: "arrow.clockwise")
                                }
                                .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.delete(m.id)
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                                Button {
                                    store.setEnabled(m.id, !m.enabled)
                                } label: {
                                    Label(m.enabled ? "Duraklat" : "Devam", systemImage: m.enabled ? "pause" : "play")
                                }
                                .tint(.orange)
                            }
                        }
                    } footer: {
                        SchedulingFootnote()
                    }
                }
            }
            .navigationTitle("İzleme")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("İzleme ekle")
                }
            }
            .sheet(isPresented: $showAdd) {
                MonitorEditView()
            }
        }
    }
}

struct SchedulingFootnote: View {
    var body: some View {
        Text("Uygulama açıkken kontroller seçtiğiniz sıklıkta yapılır. Arka planda zamanı iOS belirler (genellikle en sık 15 dakikada bir) ve hızlı kontrol yapılır: ilk 10 sayfa, sertifika ve güvenlik başlıkları.")
    }
}

private struct MonitorRow: View {
    let monitor: Monitor
    let running: Bool
    let queued: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let r = monitor.latest {
                ScoreRing(score: r.score, grade: r.grade, size: 44, lineWidth: 5)
            } else {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 5)
                    .frame(width: 44, height: 44)
                    .overlay(Text("—").foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(monitor.name).font(.headline).lineLimit(1)
                    if !monitor.enabled {
                        Image(systemName: "pause.circle.fill").foregroundStyle(.orange).font(.caption)
                    }
                }
                Text(shortURL(monitor.urlString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let diff = monitor.latest?.diff {
                    Text(diff.summary)
                        .font(.caption)
                        .foregroundStyle(diff.hasRegressions ? .red : diff.hasChanges ? .green : .secondary)
                        .lineLimit(1)
                }
                StatusLine(monitor: monitor, running: running, queued: queued)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct StatusLine: View {
    let monitor: Monitor
    let running: Bool
    let queued: Bool

    var body: some View {
        HStack(spacing: 4) {
            if running {
                ProgressView().controlSize(.mini)
                Text("Kontrol ediliyor…")
            } else if queued {
                Image(systemName: "hourglass")
                Text("Sırada")
            } else if !monitor.enabled {
                Text("Duraklatıldı · \(monitor.intervalText)")
            } else {
                Image(systemName: "clock")
                Text(monitor.intervalText)
                Text("·")
                if monitor.nextRunAt <= Date() {
                    Text("şimdi")
                } else {
                    Text(monitor.nextRunAt, style: .relative)
                    Text("sonra")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Ekle / düzenle

struct MonitorEditView: View {
    @EnvironmentObject private var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Monitor
    @State private var error: String?
    private let isNew: Bool

    init(existing: Monitor? = nil, prefillURL: String? = nil) {
        if let existing {
            _draft = State(initialValue: existing)
            isNew = false
        } else {
            _draft = State(initialValue: Monitor(name: "", urlString: prefillURL ?? "", intervalMinutes: 60))
            isNew = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ornek.com", text: $draft.urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Ad (isteğe bağlı)", text: $draft.name)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Site")
                }

                Section {
                    Picker("Sıklık", selection: $draft.intervalMinutes) {
                        ForEach(MonitorInterval.presets, id: \.self) { m in
                            Text(MonitorInterval.title(for: m)).tag(m)
                        }
                    }
                } header: {
                    Text("Zamanlama")
                } footer: {
                    if draft.intervalMinutes < 15 {
                        Text("15 dakikadan sık kontroller yalnızca uygulama açıkken yapılabilir.")
                    }
                }

                Section {
                    Stepper(value: $draft.config.maxPages, in: 5...1000, step: 5) {
                        LabeledContent("En fazla sayfa", value: "\(draft.config.maxPages)")
                    }
                    Stepper(value: $draft.config.maxDepth, in: 0...10) {
                        LabeledContent("Bağlantı derinliği", value: "\(draft.config.maxDepth)")
                    }
                    Stepper(value: $draft.config.slowPageMs, in: 500...10000, step: 500) {
                        LabeledContent("Yavaş sayfa eşiği", value: formatMs(Double(draft.config.slowPageMs)))
                    }
                    Toggle("Dış bağlantıları kontrol et", isOn: $draft.config.checkExternalLinks)
                    Toggle("robots.txt kurallarına uy", isOn: $draft.config.respectRobots)
                    Toggle("Sitemap'teki sayfaları da tara", isOn: $draft.config.useSitemap)
                    ProbeToggle(isOn: $draft.config.probeSensitivePaths)
                } header: {
                    Text("Kontrol kapsamı")
                }

                Section {
                    TextField("Ör. Hoş geldiniz", text: Binding(
                        get: { draft.config.requiredText ?? "" },
                        set: { draft.config.requiredText = $0.isEmpty ? nil : $0 }))
                } header: {
                    Text("Beklenen içerik")
                } footer: {
                    Text("Ana sayfada bu metin bulunmazsa site çalışmıyor sayılır ve bildirim gelir. Sayfa açılıp hata mesajı gösterdiğinde de kesintiyi yakalar.")
                }

                Section {
                    Toggle("Değişiklik olunca bildir", isOn: $draft.notifyOnChange)
                    Toggle("İzleme etkin", isOn: $draft.enabled)
                }

                if !isNew {
                    Section {
                        Button("Geçmişi temizle", role: .destructive) {
                            store.clearHistory(draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Yeni izleme" : "İzlemeyi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Ekle" : "Kaydet", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        guard let url = normalizeSiteURL(draft.urlString) else {
            error = "Geçerli bir adres girin (ör. ornek.com)"
            return
        }
        var m = draft
        m.urlString = url.absoluteString
        if m.name.trimmingCharacters(in: .whitespaces).isEmpty { m.name = url.host ?? url.absoluteString }
        if isNew {
            store.add(m)
            store.runNow(m.id)
        } else {
            store.update(m)
        }
        dismiss()
    }
}

// MARK: - İzleme ayrıntısı

struct MonitorDetailView: View {
    let monitorID: UUID
    @EnvironmentObject private var store: MonitorStore
    @State private var editing = false
    @State private var metric = 0

    var body: some View {
        if let m = store.monitor(monitorID) {
            content(m)
        } else {
            Text("İzleme silindi").foregroundStyle(.secondary)
        }
    }

    private func content(_ m: Monitor) -> some View {
        let running = store.runningID == m.id
        let queued = store.queue.contains(m.id)
        return List {
            Section {
                HStack(spacing: 16) {
                    if let r = m.latest {
                        ScoreRing(score: r.score, grade: r.grade, size: 80, lineWidth: 8)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(m.name).font(.headline)
                        Label(shortURL(m.urlString), systemImage: "globe")
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        StatusLine(monitor: m, running: running, queued: queued)
                        if let r = m.latest {
                            Text("Son kontrol: \(r.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)

                Button {
                    store.runNow(m.id)
                } label: {
                    Label(running ? "Kontrol ediliyor…" : "Şimdi kontrol et", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(running || queued)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))

                Toggle("İzleme etkin", isOn: Binding(
                    get: { m.enabled },
                    set: { store.setEnabled(m.id, $0) }))
            }

            if let up = UptimeStats(runs: m.runs) {
                Section {
                    UptimeCard(stats: up)
                } header: {
                    Text("Çalışırlık")
                }
            }

            if m.runs.count >= 2 {
                Section {
                    Picker("Grafik", selection: $metric) {
                        Text("Puan").tag(0)
                        Text("Yükleme süresi").tag(1)
                        Text("Sorun").tag(2)
                    }
                    .pickerStyle(.segmented)
                    TrendChart(runs: Array(m.runs.prefix(50).reversed()), metric: metric)
                        .frame(height: 180)
                        .padding(.vertical, 4)
                } header: {
                    Text("Eğilim")
                }
            }

            if let latest = m.latest {
                Section {
                    if let diff = latest.diff {
                        NavigationLink {
                            RunDetailView(monitorID: m.id, run: latest)
                        } label: {
                            DiffSummaryRow(diff: diff)
                        }
                    } else {
                        Text("İlk kontrol — karşılaştırılacak önceki sonuç yok.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Son değişiklikler")
                }
            }

            Section {
                if m.runs.isEmpty {
                    Text("Henüz kontrol yapılmadı.").foregroundStyle(.secondary)
                }
                ForEach(Array(m.runs.enumerated()), id: \.element.id) { i, run in
                    NavigationLink {
                        RunDetailView(monitorID: m.id, run: run)
                    } label: {
                        RunRow(run: run, previous: m.runs.dropFirst(i + 1).first(where: { $0.quick == run.quick }))
                    }
                }
            } header: {
                Text("Geçmiş (\(m.runs.count))")
            } footer: {
                SchedulingFootnote()
            }
        }
        .navigationTitle(m.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Düzenle") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            MonitorEditView(existing: m)
        }
    }
}

private struct UptimeCard: View {
    let stats: UptimeStats

    private var color: Color {
        stats.percent >= 99.5 ? .green : stats.percent >= 95 ? .orange : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%%%.1f", stats.percent))
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                Text("çalışırlık · son \(stats.checks) kontrol")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatMs(stats.avgMs)).font(.subheadline.weight(.semibold).monospacedDigit())
                    Text("Ort. yanıt").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.avgTTFBMs.map(formatMs) ?? "—").font(.subheadline.weight(.semibold).monospacedDigit())
                    Text("Ort. ilk bayt").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.lastDown.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Yok")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(stats.lastDown == nil ? Color.green : Color.red)
                    Text("Son kesinti").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TrendChart: View {
    let runs: [MonitorRun]
    let metric: Int

    private func value(_ r: MonitorRun) -> Double {
        switch metric {
        case 1: return r.avgMs
        case 2: return Double(r.problemCount)
        default: return Double(r.score)
        }
    }

    private var label: String {
        switch metric {
        case 1: return "ms"
        case 2: return "Sorun"
        default: return "Puan"
        }
    }

    var body: some View {
        Chart(runs) { r in
            LineMark(x: .value("Tarih", r.date), y: .value(label, value(r)))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            PointMark(x: .value("Tarih", r.date), y: .value(label, value(r)))
                .symbolSize(r.diff?.hasRegressions == true ? 60 : 24)
                .foregroundStyle(r.diff?.hasRegressions == true ? Color.red : Color.accentColor)
        }
        .chartYScale(domain: metric == 0 ? 0.0...100.0 : 0.0...max(1.0, (runs.map(value).max() ?? 1.0) * 1.15))
    }
}

private struct RunRow: View {
    let run: MonitorRun
    let previous: MonitorRun?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                    Text(run.quick ? "Hızlı" : "Tam")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((run.quick ? Color.orange : Color.accentColor).opacity(0.14), in: Capsule())
                        .foregroundStyle(run.quick ? Color.orange : Color.accentColor)
                }
                Text(run.diff?.summary ?? "İlk kontrol")
                    .font(.caption)
                    .foregroundStyle(run.diff?.hasRegressions == true ? .red : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(run.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ScoreRing.color(for: run.score))
                if let p = previous, p.score != run.score {
                    let d = run.score - p.score
                    Text(d > 0 ? "+\(d)" : "\(d)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(d > 0 ? .green : .red)
                }
            }
        }
    }
}

private struct DiffSummaryRow: View {
    let diff: ScanDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: diff.hasRegressions ? "arrow.down.right.circle.fill"
                      : diff.hasChanges ? "arrow.up.right.circle.fill" : "equal.circle.fill")
                    .foregroundStyle(diff.hasRegressions ? .red : diff.hasChanges ? .green : .secondary)
                    .font(.title3)
                Text(diff.summary).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(diff.previousRunDate.formatted(date: .abbreviated, time: .shortened)) tarihli kontrole göre")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tek kontrolün ayrıntısı ve farklar

struct RunDetailView: View {
    let monitorID: UUID
    let run: MonitorRun
    @EnvironmentObject private var store: MonitorStore
    @State private var report: ScanReport?
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                LabeledContent("Tarih", value: run.date.formatted(date: .long, time: .standard))
                LabeledContent("Tür", value: run.quick ? "Hızlı (arka plan)" : "Tam")
                LabeledContent("Süre", value: String(format: "%.1f sn", run.durationSec))
                LabeledContent("Puan", value: "\(run.score) (\(run.grade))")
                if let report {
                    NavigationLink {
                        ReportView(report: report)
                    } label: {
                        Label("Tam raporu aç", systemImage: "doc.text.magnifyingglass")
                    }
                } else if loaded {
                    Text("Rapor dosyası bulunamadı").foregroundStyle(.secondary)
                }
            }

            if let d = run.diff {
                DiffSections(diff: d)
            } else {
                Section {
                    Text("Bu ilk kontrol; karşılaştırılacak önceki sonuç yok.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(run.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            report = store.report(for: run)
            loaded = true
        }
    }
}

struct DiffSections: View {
    let diff: ScanDiff

    var body: some View {
        Group {
        Section {
            CompareRow(title: "Sağlık puanı", old: "\(diff.oldScore)", new: "\(diff.newScore)",
                       better: diff.newScore > diff.oldScore, worse: diff.newScore < diff.oldScore)
            CompareRow(title: "Ort. yükleme", old: formatMs(diff.oldAvgMs), new: formatMs(diff.newAvgMs),
                       better: diff.newAvgMs < diff.oldAvgMs * 0.8, worse: diff.newAvgMs > diff.oldAvgMs * 1.25)
            CompareRow(title: "Taranan sayfa", old: "\(diff.oldPageCount)", new: "\(diff.newPageCount)",
                       better: false, worse: false)
        } header: {
            Text("\(diff.previousRunDate.formatted(date: .abbreviated, time: .shortened)) ile karşılaştırma")
        }

        if !diff.hasChanges {
            Section {
                Label("Önceki kontrole göre değişiklik yok", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }

        if !diff.newIssues.isEmpty {
            Section {
                ForEach(diff.newIssues) { ChangeIssueRow(issue: $0, resolved: false) }
            } header: {
                DiffHeader(title: "Yeni sorunlar", count: diff.newIssues.count, color: .red)
            }
        }

        if !diff.resolvedIssues.isEmpty {
            Section {
                ForEach(diff.resolvedIssues) { ChangeIssueRow(issue: $0, resolved: true) }
            } header: {
                DiffHeader(title: "Çözülen sorunlar", count: diff.resolvedIssues.count, color: .green)
            }
        }

        }
        Group {
        if !diff.statusChanges.isEmpty {
            Section {
                ForEach(diff.statusChanges) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shortURL(c.url)).font(.subheadline).lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text(c.oldText).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption2)
                            Text(c.newText).foregroundStyle(c.worse ? .red : .green)
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
            } header: {
                DiffHeader(title: "Durumu değişen sayfalar", count: diff.statusChanges.count, color: .orange)
            }
        }

        if !diff.newlyBroken.isEmpty {
            Section {
                ForEach(diff.newlyBroken, id: \.self) { URLRow(url: $0, icon: "xmark.circle.fill", color: .red) }
            } header: {
                DiffHeader(title: "Yeni bozulan kaynaklar", count: diff.newlyBroken.count, color: .red)
            }
        }

        if !diff.fixedResources.isEmpty {
            Section {
                ForEach(diff.fixedResources, id: \.self) { URLRow(url: $0, icon: "checkmark.circle.fill", color: .green) }
            } header: {
                DiffHeader(title: "Düzelen kaynaklar", count: diff.fixedResources.count, color: .green)
            }
        }

        if !diff.slowerPages.isEmpty {
            Section {
                ForEach(diff.slowerPages) { TimingRow(change: $0) }
            } header: {
                DiffHeader(title: "Yavaşlayan sayfalar", count: diff.slowerPages.count, color: .orange)
            }
        }

        if !diff.fasterPages.isEmpty {
            Section {
                ForEach(diff.fasterPages) { TimingRow(change: $0) }
            } header: {
                DiffHeader(title: "Hızlanan sayfalar", count: diff.fasterPages.count, color: .green)
            }
        }

        }
        Group {
        if !diff.addedPages.isEmpty {
            Section {
                ForEach(diff.addedPages, id: \.self) { URLRow(url: $0, icon: "plus.circle.fill", color: .accentColor) }
            } header: {
                DiffHeader(title: "Yeni sayfalar", count: diff.addedPages.count, color: .accentColor)
            }
        }

        if !diff.removedPages.isEmpty {
            Section {
                ForEach(diff.removedPages, id: \.self) { URLRow(url: $0, icon: "minus.circle.fill", color: .orange) }
            } header: {
                DiffHeader(title: "Artık bulunamayan sayfalar", count: diff.removedPages.count, color: .orange)
            }
        }

        if !diff.certChanges.isEmpty {
            Section {
                ForEach(diff.certChanges, id: \.self) { Label($0, systemImage: "lock.shield") }
            } header: {
                Text("Sertifika")
            }
        }
        }
    }
}

private struct DiffHeader: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
            Spacer()
            Text("\(count)")
        }
    }
}

private struct CompareRow: View {
    let title: String
    let old: String
    let new: String
    let better: Bool
    let worse: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(old).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Text(new)
                .fontWeight(.semibold)
                .foregroundStyle(worse ? .red : better ? .green : .primary)
        }
        .font(.subheadline.monospacedDigit())
    }
}

private struct ChangeIssueRow: View {
    let issue: ScanDiff.IssueChange
    let resolved: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if resolved {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                SeverityIcon(severity: issue.severity)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(resolved, color: .secondary)
                if !issue.detail.isEmpty {
                    Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                }
                Text(shortURL(issue.url))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct URLRow: View {
    let url: String
    let icon: String
    let color: Color

    var body: some View {
        Label {
            Text(shortURL(url)).font(.caption.monospaced()).lineLimit(2).truncationMode(.middle)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .contextMenu {
            Button { UIPasteboard.general.string = url } label: { Label("Adresi kopyala", systemImage: "doc.on.doc") }
        }
    }
}

private struct TimingRow: View {
    let change: ScanDiff.TimingChange

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(shortURL(change.url)).font(.subheadline).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 6) {
                Text(formatMs(change.oldMs)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2)
                Text(formatMs(change.newMs)).foregroundStyle(change.newMs > change.oldMs ? .red : .green)
            }
            .font(.caption.monospacedDigit())
        }
    }
}
