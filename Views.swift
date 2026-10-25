import SwiftUI
import AVKit

struct RootView: View {
    @EnvironmentObject var c:Connection
    var body: some View {
        Group {
            if c.connected {
                VStack(spacing:0) {
                    HStack {
                        Circle().fill(c.online ? Color.green : Color.orange).frame(width:8,height:8)
                        Text(c.message).font(.caption).lineLimit(2)
                        Spacer()
                    }.padding(12).background(Color.white.opacity(0.05))
                    TabView {
                        ControlView().tabItem { Label("Machine",systemImage:"slider.horizontal.3") }
                        StretchView().tabItem { Label("Stretch",systemImage:"arrow.up.and.down") }
                        ModesView().tabItem { Label("Modes",systemImage:"waveform.path") }
                        SettingsView().tabItem { Label("Instellen",systemImage:"gearshape") }
                    }
                    VStack(spacing:6) {
                        Button { Task { await c.send("stop") } } label: {
                            Label("STOP MACHINE",systemImage:"stop.fill").font(.headline).frame(maxWidth:.infinity).padding(13)
                        }.buttonStyle(.borderedProminent).tint(.red)
                        Text(c.receipt.isEmpty ? "STOP vereist een actieve lokale wifi-verbinding." : c.receipt)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading)
                    }.padding(.horizontal).padding(.bottom,8)
                }.task { c.resume() }
            } else { ConnectView() }
        }
    }
}
struct ConnectView: View {
    @EnvironmentObject var c:Connection
    @State private var url="http://192.168.4.1/api"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image("RemoteLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width:88,height:88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.vertical, 6)
                    Text("Machine Remote · LOKAAL v3").font(.title.bold())
                    Text("APPVERSIE 3.0 · DIRECTE WIFI").font(.caption).foregroundStyle(Color(red:0.92,green:1,blue:0))
                    Text("Verbind eerst met de MachineRemote-ESP8266 hotspot.").foregroundStyle(.secondary)
                }
                Section("Verbinden met jouw machine") {
                    TextField("http://192.168.4.1/api",text:$url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { Task { await c.connect(url:url) } } label: {
                        HStack { Text("Verbinden"); Spacer(); Image(systemName:"network") }
                    }.disabled(url.isEmpty)
                }
                Section { Text(c.message).font(.footnote) }
                Section {
                    Text("LOKAAL v3 — Rechtstreekse wifi-verbinding. Geen koppelcode, geen webserver. Eerst verbinding maken met MachineRemote-ESP8266.")
                }.font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Welkom")
        }
    }
}
struct CommandButton: View {
    @EnvironmentObject var c:Connection
    let title:String
    let command:String
    var body: some View {
        Button(title) { Task { await c.send(command) } }.disabled(!c.online || c.sending)
    }
}
struct ControlView: View {
    @EnvironmentObject var c:Connection
    @AppStorage("videoURL") private var videoURL=""
    @State private var player:AVPlayer?
    @State private var videoMessage=""
    var body: some View {
        NavigationStack {
            Form {
                Section("Machine") {
                    HStack {
                        Text(c.flag("session") ? "Sessie actief" : "Sessie uit").font(.title2.bold())
                        Spacer(); Text("\(c.number("pct"))%").font(.title.bold()).foregroundStyle(Color(red:0.92,green:1,blue:0))
                    }
                    ProgressView(value:Double(c.number("pct")),total:100)
                    Text(c.text("ai")).font(.callout)
                    Text(c.text("state")).font(.caption).foregroundStyle(.secondary)
                    CommandButton(title:"Start machine",command:"start")
                    CommandButton(title:"Terug naar beginsensor",command:"return_home")
                }
                Section("Terugmelding") {
                    LabeledContent("Beweging",value:c.flag("moving") ? "Aan" : "Uit")
                    LabeledContent("Kalibratie",value:c.flag("calibrated") ? "Gereed" : "Nog nodig")
                    Text(c.text("relay"))
                    CommandButton(title:c.flag("squirtDisabled") ? "Relais vrijgeven" : "Relais uitschakelen",command:"tog_sqdisable")
                }
                Section("Video op deze iPhone") {
                    TextField("Directe HTTPS-video-URL",text:$videoURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Video openen") {
                        guard let u=URL(string:videoURL),u.scheme=="https" else { videoMessage="Gebruik een HTTPS-video-URL"; return }
                        player?.pause(); player=AVPlayer(url:u); videoMessage=""
                    }
                    if !videoMessage.isEmpty { Text(videoMessage).font(.caption) }
                    if let player { VideoPlayer(player:player).frame(height:190) }
                    Text("Directe MP4/HLS-stream. Geen YouTube- of Vimeo-webpagina. Video bestuurt de machine niet.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Machine")
        }.onDisappear { player?.pause() }
    }
}
struct NumericSetting: View {
    @EnvironmentObject var c:Connection
    let title:String
    let key:String
    let prefix:String
    let range:ClosedRange<Int>
    let step:Int
    @State private var value=0
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Stepper("\(title): \(value)",value:$value,in:range,step:step)
            HStack {
                Text("Machine: \(c.number(key))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Toepassen") { Task { await c.send(prefix+String(value)) } }.disabled(!c.online || c.sending)
            }
        }.onAppear { value=min(range.upperBound,max(range.lowerBound,c.number(key))) }
    }
}
struct StretchView: View {
    @EnvironmentObject var c:Connection
    var body: some View {
        NavigationStack {
            Form {
                Section("Bediening") {
                    LabeledContent("Stretch",value:c.flag("stretchActive") ? "Actief" : "Uit")
                    CommandButton(title:"Start stretch",command:"stretch_on")
                    CommandButton(title:"Stop stretch direct",command:"stretch_off")
                    Text("Internetbediening gebruikt Start en Stop. Loslaten van het scherm is geen stopfunctie.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Instellingen") {
                    LabeledContent("Type",value:c.text("stretchModeSelect"))
                    CommandButton(title:"Stappen met pauze",command:"stretch_mode_stops")
                    CommandButton(title:"Ultra slow",command:"stretch_mode_ultra")
                    NumericSetting(title:"Afstand (%)",key:"stretchStepPct",prefix:"stretch_step_",range:0...100,step:5)
                    NumericSetting(title:"Snelheid (%)",key:"stretchSpeedPct",prefix:"stretch_speed_",range:0...100,step:5)
                    NumericSetting(title:"Pauze (sec)",key:"stretchWaitSec",prefix:"stretch_wait_",range:5...120,step:5)
                }
                Section("Bestaande extra modes") {
                    ModeRow(title:"Omgekeerde bediening",key:"stretchLatch",command:"stretch_latch_toggle")
                    CommandButton(title:"Latch activeren",command:"stretch_latch_press")
                    ModeRow(title:"Strafmodus",key:"stretchPunish",command:"stretch_punish_toggle")
                    NumericSetting(title:"Type (0–8)",key:"stretchPunishType",prefix:"stretch_punish_type_",range:0...8,step:1)
                    NumericSetting(title:"Duur (sec)",key:"stretchPunishTime",prefix:"stretch_punish_time_",range:10...120,step:5)
                    Text("De globale STOP beëindigt alle modes direct in de firmware zodra deze opdracht aankomt.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Stretch")
        }
    }
}
struct ModeRow: View {
    @EnvironmentObject var c:Connection
    let title:String
    let key:String
    let command:String
    var body: some View {
        Button { Task { await c.send(command) } } label: {
            HStack { Text(title).foregroundStyle(.primary); Spacer(); Text(c.flag(key) ? "AAN" : "UIT").foregroundStyle(c.flag(key) ? Color.yellow : Color.secondary) }
        }.disabled(!c.online || c.sending)
    }
}
struct ModesView: View {
    @EnvironmentObject var c:Connection
    let modes:[(String,String)]=[("Edge tease","edge"),("Resistance","resistance"),("Heartbeat","heartbeat"),("Overload","overload"),("Lock-in","lockin"),("Punishment","punishment"),("Ghost","ghost"),("Flow","flow"),("Instinct","instinct"),("Predator","predator"),("Hunter","hunter"),("Ruin","ruin"),("Chaos squirt","chaossquirt")]
    var body: some View {
        NavigationStack {
            Form {
                Section("Sterkte") {
                    NumericSetting(title:"Intensiteit (%)",key:"extremeIntensity",prefix:"extreme_int_",range:0...100,step:5)
                    NumericSetting(title:"Chaos (%)",key:"chaosSquirtPct",prefix:"chaos_sq_",range:0...100,step:5)
                }
                Section("Modes") {
                    ForEach(modes,id:\.1) { item in ModeRow(title:item.0,key:item.1,command:"toggle_"+item.1) }
                }
                Section("Presets") {
                    CommandButton(title:"Alle modes uit",command:"preset_0")
                    ForEach(1...5,id:\.self) { i in CommandButton(title:"Preset \(i)",command:"preset_\(i)") }
                }
                Section { CommandButton(title:"Start machine",command:"start") }
            }.navigationTitle("Modes")
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var c:Connection
    @State private var confirmHoming=false
    @State private var confirmDisconnect=false
    var body: some View {
        NavigationStack {
            Form {
                Section("Kalibratie en bereik") {
                    Button("Kalibreren: volledig sensor tot sensor") { confirmHoming=true }.disabled(!c.online || c.sending)
                    CommandButton(title:"Start instelcyclus",command:"start_cycles")
                    CommandButton(title:"Beginpunt opslaan",command:"set_begin")
                    CommandButton(title:"Eindpunt opslaan",command:"set_end")
                    CommandButton(title:"Begin/eindpunten resetten",command:"reset_points")
                    NumericSetting(title:"Eindafstand (cm)",key:"maxEndCm",prefix:"save_max_end_cm_",range:0...40,step:1)
                    Text(c.text("manual")).font(.caption)
                }
                Section("Verbinding") {
                    Text(c.credentials?.url ?? "").font(.caption).textSelection(.enabled)
                    LabeledContent("Firmware",value:c.text("fw"))
                    Text("De ESP8266 stopt de beweging als de app stopt met communiceren. Een fysieke noodstop blijft noodzakelijk.").font(.footnote)
                    Text("Lokaal wifi-systeem. Eerst onbelast testen; een fysieke noodstop blijft nodig.").font(.footnote).foregroundStyle(.orange)
                    Button("Verbinding verwijderen",role:.destructive) { confirmDisconnect=true }
                }
            }.navigationTitle("Instellen")
                .confirmationDialog("De machine doorloopt het volledige sensorbereik.",isPresented:$confirmHoming,titleVisibility:.visible) {
                    Button("Kalibratie starten") { Task { await c.send("homing") } }
                }
                .confirmationDialog("Verbinding verwijderen? Daarna vul je opnieuw alleen het API-adres in.",isPresented:$confirmDisconnect,titleVisibility:.visible) {
                    Button("Verwijderen",role:.destructive) { Task { await c.disconnect() } }
                }
        }
    }
}
