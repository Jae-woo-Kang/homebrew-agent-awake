# AgentAwake

AgentAwake는 Codex와 Claude Code의 실행 위치를 보여주고, 필요할 때 Mac의
시스템 잠자기를 막아 주는 macOS 메뉴바 앱입니다.

메뉴바 아이콘을 누르면 다음 상태를 한눈에 볼 수 있습니다.

- Codex: CLI / VS Code Extension / macOS App
- Claude Code: CLI / VS Code Extension / macOS App
- 에이전트 실행 여부와 독립적으로 동작하는 `Mac 잠자기 방지` 토글

> AgentAwake의 “실행 중” 표시는 프로세스나 앱이 열려 있다는 뜻입니다.
> 모델이 현재 응답을 생성하는 중인지와 입력을 기다리는 중인지는 구분하지 않습니다.

## 요구 사항

- macOS 13 Ventura 이상
- Apple Silicon 또는 Intel Mac
- 덮개 닫힘 모드를 사용할 때 관리자 승인

## Homebrew로 설치

```bash
brew tap Jae-woo-Kang/agent-awake
brew trust Jae-woo-Kang/agent-awake
brew install --cask agent-awake
open -a AgentAwake
```

Homebrew의 `trust` 단계는 서드파티 tap에서 macOS 앱을 설치한다는 사실을
사용자가 명시적으로 승인하는 절차입니다. 저장소 주소와 소유자가
`Jae-woo-Kang/homebrew-agent-awake`인지 확인한 뒤 실행하세요.

업데이트:

```bash
brew update
brew upgrade --cask agent-awake
```

삭제:

```bash
brew uninstall --cask agent-awake
```

AgentAwake는 메뉴바 전용 앱이라 Dock에는 나타나지 않습니다. 메뉴바에서
방패 모양 아이콘을 찾으세요. 잠자기 방지를 전환하는 동안에도 아이콘의
위치와 모양은 그대로 유지됩니다.

현재 공개 베타가 Developer ID로 공증되지 않은 경우 첫 실행을 macOS가 막을
수 있습니다. 이때 **시스템 설정 → 개인정보 보호 및 보안**에서 AgentAwake의
**확인 없이 열기(Open Anyway)**를 선택하세요. 출처를 확인할 수 없는 다른
경로에서 받은 앱에는 이 예외를 적용하지 마세요.

## 사용법

1. 메뉴바에서 AgentAwake 아이콘을 누릅니다.
2. Codex와 Claude Code의 CLI, VS Code, App 상태를 확인합니다.
3. Mac을 계속 실행하려면 `Mac 잠자기 방지`를 켭니다.
4. 덮개를 닫은 상태에서도 유지해야 할 때만 별도의 `덮개를 닫아도 유지`
   토글을 켜고 macOS 관리자 창을 승인합니다.
5. 작업이 끝나면 `Mac 잠자기 방지` 토글을 끕니다.

토글은 Codex나 Claude의 실행 여부와 무관합니다. 두 프로그램이 모두 꺼져
있어도 토글이 켜져 있으면 Mac의 시스템과 네트워크는 계속 작동합니다.
디스플레이는 별도로 꺼질 수 있습니다. 기본 토글은 관리자 창이나 외부
프로세스를 실행하지 않으므로 메뉴 창이 열린 상태에서 즉시 전환됩니다.

`덮개를 닫아도 유지`는 선택 기능입니다. 이 토글은 관리자 승인 창에 포커스를
넘기므로 메뉴 창이 잠시 닫힐 수 있지만 메뉴바 아이콘과 기본 잠자기 방지는
유지됩니다.

## 안전장치

덮개가 열려 있을 때의 유휴 잠자기는 macOS IOKit power assertion으로
막습니다. 별도의 `덮개를 닫아도 유지` 토글을 켠 경우에만 관리자 권한으로
`SleepDisabled` 설정을 임시 적용하는 가디언이 함께 실행됩니다.

가디언은 다음 조건에서 원래 전원 설정을 복구합니다.

- 앱의 heartbeat가 25초 이상 끊김
- AgentAwake 종료
- 사용자가 토글을 끔
- 배터리 20% 이하(배터리 사용 중)
- 12시간 경과
- macOS가 심각한 CPU thermal throttling을 보고함

MacBook을 가방이나 환기가 되지 않는 공간에서 실행하지 마세요. 소프트웨어
안전장치는 충분한 공기 흐름을 대신할 수 없습니다.

### 비정상 종료 후 수동 복구

관리자 가디언 자체가 강제 종료되는 등 정상 cleanup이 불가능했다면 다음
명령으로 기본 덮개 잠자기를 복구할 수 있습니다.

```bash
sudo pmset -a disablesleep 0
```

현재 설정 확인:

```bash
pmset -g | grep SleepDisabled
```

## 감지 방식과 한계

| 대상 | 감지 방식 | 참고 |
|---|---|---|
| Codex CLI | 실행 파일명이 정확히 `codex`인지 확인 | 독립 실행만 CLI로 표시 |
| Claude Code CLI | 실행 파일명이 정확히 `claude`인지 확인 | 독립 실행만 CLI로 표시 |
| Codex VS Code | 확장 경로, App Server, VS Code 부모 프로세스 조합 | 확장 구현 변경 시 보완 필요 |
| Claude Code VS Code | 확장 경로, IDE 모드, VS Code 부모 프로세스 조합 | 확장 구현 변경 시 보완 필요 |
| macOS App | 실행 앱 이름, bundle ID, bundle path 확인 | 앱이 열려 있으면 실행 중으로 표시 |

VS Code 확장은 독립 앱이 아니라 Extension Host 안에서 실행되므로, 버전별
프로세스 구조 변화에 따라 감지 규칙이 업데이트될 수 있습니다. 잘못 감지되는
사례가 있으면 실행 환경과 앱 버전을 포함해 이슈를 남겨 주세요.

## 소스에서 빌드

Xcode Command Line Tools와 Swift 5.9 이상이 설치된 Mac에서:

```bash
git clone https://github.com/Jae-woo-Kang/homebrew-agent-awake.git
cd homebrew-agent-awake
swift test
scripts/build-app.sh
scripts/install-local.sh
```

`scripts/build-app.sh`는 arm64와 x86_64를 포함한 universal 앱을
`dist/AgentAwake.app`에 생성합니다.

## 배포 메모

GitHub Actions는 모든 push에서 macOS 테스트와 universal build를 수행합니다.
`v*` 태그를 push하면 해당 버전의 ZIP을 GitHub Release에 게시합니다.

공개 베타 릴리스는 ad-hoc 서명될 수 있습니다. Developer ID 배포 시 빌드
환경에 `AGENTAWAKE_CODESIGN_IDENTITY`를 제공하고 Apple notarization 단계를
추가해야 Gatekeeper 경고 없는 배포가 가능합니다.

## 라이선스

[MIT](LICENSE)
