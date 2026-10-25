// HgsWindowAbility 的实现位于 hgs HAR 内; module.json5 的 srcEntry 要求
// 路径在 entry 模块内, 且运行时以 default 导出加载 Ability 类 — 此文件
// 同时提供 default 与具名导出。
import { HgsWindowAbility as HgsWindowAbilityImpl } from 'hgs';

export default HgsWindowAbilityImpl;
export { HgsWindowAbilityImpl as HgsWindowAbility };
