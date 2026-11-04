import SwiftUI

enum AppLinks {
    static let privacy = URL(string: "https://alpp.studio/monsite/privacy/")!
    static let support = URL(string: "https://alpp.studio/monsite/")!
    static let contactEmail = "help@alpp.studio"
    static let mail = URL(string: "mailto:help@alpp.studio?subject=MonSite")!
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        BrandMark(size: 84)
                        Text("MonSite").font(.title2.weight(.bold))
                        Text("Sürüm \(version)").font(.footnote).foregroundStyle(.secondary)
                        Text("Web sitelerinizin bağlantılarını, hızını, güvenlik başlıklarını ve SSL sertifikasını denetler; düzenli kontrollerle değişiklikleri takip eder.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Label {
                        Text("MonSite hiçbir kişisel veri toplamaz. Tarama sonuçları yalnızca bu cihazda saklanır; sunucuya gönderilmez.")
                    } icon: {
                        Image(systemName: "hand.raised.fill").foregroundStyle(Color.brand)
                    }
                    Link(destination: AppLinks.privacy) {
                        Label("Gizlilik politikası", systemImage: "lock.doc")
                    }
                } header: {
                    Text("Gizlilik")
                }

                Section {
                    Link(destination: AppLinks.support) {
                        Label("Destek", systemImage: "questionmark.circle")
                    }
                    Link(destination: AppLinks.mail) {
                        LabeledContent {
                            Text(AppLinks.contactEmail).foregroundStyle(.secondary)
                        } label: {
                            Label("E-posta gönder", systemImage: "envelope")
                        }
                    }
                } header: {
                    Text("Yardım")
                }

                Section {
                    Text("Taramaları yalnızca size ait veya test izniniz olan sitelerde yapın. MonSite, herkese açık sayfaları normal bir tarayıcı gibi ziyaret eder; güvenlik kontrolleri pasif ve yüzeyseldir ve bir sızma testinin yerini tutmaz.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Sorumlu kullanım")
                }
            }
            .navigationTitle("Hakkında")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }
}
