# AgentAwake

[한국어](README_kor.md) | [English](README_eng.md)

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
- 전원 도우미를 처음 설치할 때 한 번의 관리자 승인

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
눈 모양 아이콘을 찾으세요. 잠자기 방지가 꺼져 있으면 윤곽 눈, 켜져 있으면
채워진 눈, 전환 중에는 점 3개 아이콘으로 표시됩니다. 메뉴 창 바깥을 클릭하면
메뉴 창만 닫히고 앱과 잠자기 방지 상태는 계속 유지됩니다. 앱을 열어도 별도의
일반 창이나 빈 설정 화면은 생성되지 않습니다.

현재 공개 베타가 Developer ID로 공증되지 않은 경우 첫 실행을 macOS가 막을
수 있습니다. 아래 절차는 이 저장소의 Homebrew tap 또는 GitHub Release에서
직접 설치한 AgentAwake에만 사용하세요. 출처를 확인할 수 없는 다른 앱에는
보안 예외를 적용하지 마세요.

### macOS 보안 경고 해제

1. 현재 표시된 보안 경고 창에서 **완료**를 클릭합니다.
2. Mac의 **시스템 설정**을 엽니다.
3. **개인정보 보호 및 보안**을 선택합니다.
4. 아래쪽의 **보안** 영역까지 스크롤합니다.
5. `“AgentAwake”은(는) 사용이 차단되었습니다` 메시지 옆의 **그래도 열기**를
   클릭합니다. macOS 버전에 따라 버튼이 **확인 없이 열기**로 표시될 수 있습니다.
6. Touch ID 또는 Mac 로그인 암호로 승인합니다.
7. 다시 표시되는 확인 창에서 **열기**를 선택합니다.

## 사용법

1. 메뉴바에서 AgentAwake 아이콘을 누릅니다.
2. Codex와 Claude Code의 CLI, VS Code, App 상태를 확인합니다.
3. Mac을 계속 실행하려면 `Mac 잠자기 방지`를 켭니다.
4. 작업이 끝나면 `Mac 잠자기 방지` 토글을 끕니다.

토글은 Codex나 Claude의 실행 여부와 무관합니다. 두 프로그램이 모두 꺼져
있어도 토글이 켜져 있으면 Mac의 시스템과 네트워크는 계속 작동합니다.
디스플레이는 별도로 꺼질 수 있습니다. `Mac 잠자기 방지` 하나만 켜면 유휴
상태의 자동 잠자기와 덮개를 닫을 때의 잠자기를 함께 막습니다. 처음 켤 때만
표시되는 macOS 관리자 승인 창에서 제한형 전원 도우미를 설치합니다. 설치가
끝난 뒤에는 앱을 다시 실행해도 토글만 누르면 비밀번호 없이 바로 적용됩니다.

## 잠자기 방지 방식

유휴 잠자기는 macOS IOKit power assertion으로 막고, 덮개 닫힘 잠자기는
최초 한 번 설치된 전원 도우미가 `SleepDisabled` 설정을 임시 적용해 막습니다.
도우미는 임의 명령을 받지 않고 설치를 승인한 사용자 소유의 요청 파일만
검증해 잠자기 방지를 켜고 끕니다. 별도 덮개 토글은 없으며 두 동작은 하나의
토글로 함께 켜지고 꺼집니다.

전원 도우미는 다음 조건에서 원래 전원 설정을 복구합니다.

- 사용자가 토글을 끔
- AgentAwake 종료 또는 앱 응답 중단
- 배터리 20% 이하(배터리 사용 중)
- 12시간 경과
- macOS가 심각한 CPU thermal throttling을 보고함

MacBook을 가방이나 환기가 되지 않는 공간에서 실행하지 마세요. 덮개가 닫혀도
발열할 수 있으며 소프트웨어 안전장치는 충분한 공기 흐름을 대신할 수 없습니다.

정상 해제가 되지 않은 경우 다음 명령으로 기본 잠자기 동작을 복구할 수 있습니다.

```bash
sudo pmset -a disablesleep 0
```

Homebrew로 AgentAwake를 삭제하면 설치된 전원 도우미도 관리자 권한으로 함께
제거됩니다.

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
