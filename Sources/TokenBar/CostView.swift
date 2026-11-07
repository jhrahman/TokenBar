import SwiftUI
import Charts
import TokenBarCore

enum CostWindow {
    @MainActor static func show() {
        GlassWindow.show(key: "cost", size: NSSize(width: 560, height: 660)) { CostView(store: .shared) }
    }
}

enum Period: String, CaseIterable, Identifiable {
    case five = "5 hours", week = "Week", cycle = "Billing cycle"
    var id: String { rawValue }
}

private func modelColor(_ model: String) -> Color {
    let m = model.lowercased()
    if m.contains("opus") { return ember }
    if m.contains("sonnet") { return mint }
    if m.contains("haiku") { return Color(red: 0.36, green: 0.62, blue: 1) }
    if m.contains("fable") || m.contains("mythos") { return Color(red: 0.7, green: 0.55, blue: 1) }
    return .gray
}

struct CostView: View {
    @ObservedObject var store: UsageStore
    @State private var period: Period = .cycle
    @State private var cumulative = false
    @State private var hover: CostBucket?

    var body: some View {
        Group {
            if let r = store.costReport { content(r) }
            else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(store.monitorClaude ? "Reading Claude Code logs…" : "Turn on Claude monitoring in Settings.")
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { store.updateCosts() }
    }

    // MARK: data for the selected period
    func range(_ r: CostReport) -> DateRange? {
        switch period { case .five: return r.fiveRange; case .week: return r.weekRange; case .cycle: return r.cycleRange }
    }
    func total(_ r: CostReport, _ p: Period) -> Double? {
        switch p { case .five: return r.fiveHour; case .week: return r.weekly; case .cycle: return r.cycle }
    }
    func step(_ p: Period) -> TimeInterval { p == .five ? 3600 : 86400 }
    var unit: Calendar.Component { period == .five ? .hour : .day }
    /// Buckets line up with clock hours / calendar days so bars sit under their axis labels.
    func aligned(_ r: DateRange) -> DateRange {
        let cal = Calendar.current
        let start = period == .five ? cal.dateInterval(of: .hour, for: r.start)!.start : cal.startOfDay(for: r.start)
        return DateRange(start: start, end: r.end)
    }

    func content(_ r: CostReport) -> some View {
        let rng = range(r) ?? r.cycleRange
        let within = r.entries.filter { $0.date >= rng.start && $0.date < rng.end }
        let buckets = CostMath.buckets(within, range: aligned(rng), step: step(period))
        let models = Set(r.entries.filter { $0.date >= rng.start && $0.date < rng.end }.map(\.model)).sorted()
        let perModel = Dictionary(grouping: r.entries.filter { $0.date >= rng.start && $0.date < rng.end }, by: \.model)
            .mapValues { $0.reduce(0) { $0 + $1.cost } }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ProviderLogo(provider: .claude, size: 22)
                Text("Claude cost on this Mac").font(.title2.bold())
            }.padding(.top, 26)

            // Period cards double as the selector.
            HStack(spacing: 10) {
                ForEach(Period.allCases) { p in card(p, r) }
            }

            if period == .cycle { cycleProgress(r) }

            // Hover readout (or a hint).
            VStack(alignment: .leading, spacing: 2) {
                if let h = hover {
                    Text("\(label(h, rng)) · \(Money.format(h.total))").font(.callout.weight(.semibold))
                    Text(h.perModel.sorted { $0.value > $1.value }
                        .map { "\(Pricing.displayName($0.key)) \(Money.format($0.value))" }.joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Hover the chart for details").font(.callout).foregroundStyle(.secondary)
                    Text(" ").font(.caption)
                }
            }
            .frame(height: 38, alignment: .topLeading)

            Picker("", selection: $cumulative) {
                Text("Per \(period == .five ? "hour" : "day")").tag(false)
                Text("Running total").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240)

            chart(buckets, models: models, rng: rng)
                .frame(height: 215)

            // Per-model breakdown.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(perModel.sorted { $0.value > $1.value }, id: \.key) { m, v in
                    HStack {
                        Circle().fill(modelColor(m)).frame(width: 8, height: 8)
                        Text(Pricing.displayName(m))
                        Spacer()
                        Text(Money.format(v)).monospacedDigit()
                    }.font(.callout)
                }
            }

            Spacer(minLength: 0)
            Text("Estimates from Claude Code logs on this Mac at API list prices: the value of the tokens, not a charge. Usage on other devices or claude.ai is not included, but the % bars in the popover count everything."
                 + (r.unpriced.isEmpty ? "" : " Not priced: \(r.unpriced.joined(separator: ", "))."))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24).padding(.bottom, 18)
    }

    func card(_ p: Period, _ r: CostReport) -> some View {
        let sel = period == p
        let v = total(r, p)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { period = p; hover = nil }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.rawValue).font(.caption).foregroundStyle(.secondary)
                Text(v.map(Money.format) ?? "n/a").font(.title3.bold().monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(sel ? ember.opacity(0.2) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(sel ? ember : .white.opacity(0.08), lineWidth: sel ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(v == nil)
    }

    func cycleProgress(_ r: CostReport) -> some View {
        let c = r.cycleRange
        let day = Int(Date().timeIntervalSince(c.start) / 86400) + 1
        let days = Int((c.end.timeIntervalSince(c.start) / 86400).rounded())
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: min(Double(day), Double(days)), total: Double(days)).tint(mint)
            Text("Day \(day) of \(days) · started \(f.string(from: c.start)) · renews \(f.string(from: c.end))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    func label(_ b: CostBucket, _ rng: DateRange) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = period == .five ? "h a" : "EEE, d MMM"
        return f.string(from: b.start)
    }

    func chart(_ buckets: [CostBucket], models: [String], rng: DateRange) -> some View {
        var running = 0.0
        let cum = buckets.map { b -> (CostBucket, Double) in running += b.total; return (b, running) }
        return Chart {
            if cumulative {
                ForEach(cum, id: \.0.id) { b, total in
                    AreaMark(x: .value("Time", b.end), y: .value("USD", total)).foregroundStyle(ember.opacity(0.18))
                    LineMark(x: .value("Time", b.end), y: .value("USD", total)).foregroundStyle(ember)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).interpolationMethod(.monotone)
                }
            } else {
                ForEach(buckets) { b in
                    ForEach(b.perModel.sorted { $0.key < $1.key }, id: \.key) { m, v in
                        BarMark(x: .value("Time", b.start, unit: unit), y: .value("USD", v), width: .ratio(0.78))
                            .cornerRadius(3)
                            .foregroundStyle(by: .value("Model", Pricing.displayName(m)))
                            .opacity(hover == nil || hover?.id == b.id ? 1 : 0.45)
                    }
                }
            }
            if let h = hover {
                RuleMark(x: .value("Time", h.start, unit: unit))
                    .foregroundStyle(.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(domain: models.map(Pricing.displayName), range: models.map(modelColor))
        .chartXScale(domain: aligned(rng).start...rng.end)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel { if let d = v.as(Double.self) { Text(Money.format(d)).font(.caption2) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: period == .five ? 5 : 6)) { _ in
                AxisValueLabel(format: period == .five ? .dateTime.hour() : .dateTime.day().month(.abbreviated))
                    .font(.caption2)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let x = p.x - geo[proxy.plotAreaFrame].origin.x
                            guard let d: Date = proxy.value(atX: x) else { hover = nil; return }
                            hover = buckets.first { d >= $0.start && d < $0.end }
                        case .ended: hover = nil
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: period)
        .animation(.easeInOut(duration: 0.25), value: cumulative)
    }
}
