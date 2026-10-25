import { EmptyEglView } from 'hgs';

// hgs 窗口占位页 (helloworld 第二步): HgsWindowAbility 载入本页,
// 内容全部来自 hgs 包的 EmptyEglView (空 EGL 渲染器上屏)。
@Entry
@Component
struct HgsWindowPage {
  build() {
    Column() {
      EmptyEglView()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0d1117')
  }
}
