import ActivityKit
import SwiftUI
import WidgetKit

/// Shared ActivityAttributes name required by the `live_activities` Flutter plugin.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState

  public struct ContentState: Codable, Hashable {}

  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    return "\(id)_\(key)"
  }
}

private let sharedDefault = UserDefaults(suiteName: "group.com.acquire.english")!

struct MicroReviewLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      lockScreenView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text("AE")
            .font(.caption.weight(.bold))
            .foregroundStyle(.teal)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 4) {
            Text(string(context, "title", fallback: "碎片记忆"))
              .font(.caption2)
              .foregroundStyle(.secondary)
            Text(string(context, "word", fallback: "—"))
              .font(.headline.weight(.semibold))
              .lineLimit(1)
            Text(string(context, "gloss", fallback: ""))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(countdown(context))
            .font(.body.monospacedDigit().weight(.semibold))
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 10) {
            Link(destination: URL(string: "acquireenglish://micro-review?action=know")!) {
              Text("认识").font(.caption.weight(.semibold))
            }
            Link(destination: URL(string: "acquireenglish://micro-review?action=fuzzy")!) {
              Text("模糊").font(.caption.weight(.semibold))
            }
            Link(destination: URL(string: "acquireenglish://micro-review?action=forget")!) {
              Text("忘记").font(.caption.weight(.semibold))
            }
            Link(destination: URL(string: "acquireenglish://micro-review?action=end")!) {
              Text("结束").font(.caption.weight(.semibold))
            }
          }
          .padding(.top, 4)
        }
      } compactLeading: {
        Text("AE").font(.caption2.weight(.bold)).foregroundStyle(.teal)
      } compactTrailing: {
        Text(countdown(context))
          .font(.caption.monospacedDigit())
      } minimal: {
        Text("词").font(.caption2.weight(.bold))
      }
    }
  }

  @ViewBuilder
  private func lockScreenView(context: ActivityViewContext<LiveActivitiesAppAttributes>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("碎片记忆").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(countdown(context)).font(.body.monospacedDigit().weight(.semibold))
      }
      Text(string(context, "word", fallback: "—"))
        .font(.title3.weight(.bold))
      Text(string(context, "gloss", fallback: ""))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Text("已记 \(int(context, "ratedCount"))")
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack {
        Link("认识", destination: URL(string: "acquireenglish://micro-review?action=know")!)
        Link("模糊", destination: URL(string: "acquireenglish://micro-review?action=fuzzy")!)
        Link("忘记", destination: URL(string: "acquireenglish://micro-review?action=forget")!)
      }
      .font(.caption.weight(.semibold))
    }
    .padding()
    .activityBackgroundTint(Color.black.opacity(0.85))
  }

  private func string(
    _ context: ActivityViewContext<LiveActivitiesAppAttributes>,
    _ key: String,
    fallback: String
  ) -> String {
    sharedDefault.string(forKey: context.attributes.prefixedKey(key)) ?? fallback
  }

  private func int(
    _ context: ActivityViewContext<LiveActivitiesAppAttributes>,
    _ key: String
  ) -> Int {
    sharedDefault.integer(forKey: context.attributes.prefixedKey(key))
  }

  private func countdown(
    _ context: ActivityViewContext<LiveActivitiesAppAttributes>
  ) -> String {
    let endsAtMs = sharedDefault.double(forKey: context.attributes.prefixedKey("endsAtMs"))
    if endsAtMs > 0 {
      let remaining = max(0, Int((endsAtMs - Date().timeIntervalSince1970 * 1000) / 1000))
      return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
    let sec = int(context, "remainingSec")
    return String(format: "%02d:%02d", sec / 60, sec % 60)
  }
}
