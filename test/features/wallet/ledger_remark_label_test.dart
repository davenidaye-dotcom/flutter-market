import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/features/wallet/utils/draw_snapshot_utils.dart';

void main() {
  test('中奖备注里的玩法码显示成名次和开出的内容', () {
    expect(ledgerRemarkLabel('中奖派彩 TM-3'), '中奖派彩 冠军 3');
    expect(ledgerRemarkLabel('中奖派彩 POS-2-10'), '中奖派彩 亚军 10');
    expect(ledgerRemarkLabel('中奖派彩 LM-BIG'), '中奖派彩 冠军 大');
    expect(ledgerRemarkLabel('中奖派彩 LM-4-ODD'), '中奖派彩 第四名 单');
    expect(ledgerRemarkLabel('中奖派彩 GYH_DS'), '中奖派彩 冠亚和 大双');
    expect(ledgerRemarkLabel('中奖派彩 DT-1-T'), '中奖派彩 冠军 虎');
    expect(ledgerRemarkLabel('下注主单 笔数=6'), '下注主单 笔数=6');
  });
}
