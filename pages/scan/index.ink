<script def>
{
  "navigationBarTitleText": "识别与显示"
}
</script>

<script setup>
// 识别 + 显示：条码/二维码识别、名片门头 OCR，结果以 HUD 大字幕呈现
// 说明：本产品不做人脸识别（合规红线），只识别"物"：条码、二维码、名片、门头
export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',
    big: '准备就绪',          // HUD 大字幕
    sub: '按确认键识别',
    kind: '',                 // barcode | ocr
    errMsg: '',
  },

  onKeyDown(event) {
    if (event.code === 'Enter') this.doScan();
  },
  tapScan() { this.doScan(); },
  tapOcr() { this.doOcr(); },

  // 条码/二维码：优先用设备 BarcodeDetector，不可用时回退后端演示结果
  async doScan() {
    this.setData({ errMsg: '' });
    try {
      const det = new BarcodeDetector();
      const shot = await this.capture();
      const codes = await det.detect(shot);
      if (codes && codes.length) {
        this.setData({ kind: 'barcode', big: codes[0].rawValue || '', sub: '识别结果 · 条码' });
        this.speak(codes[0].rawValue || '');
        return;
      }
    } catch (e) {
      // 设备不支持时走后端
    }
    fetch(this.data.apiBase + '/api/ocr?kind=barcode')
      .then((r) => r.json())
      .then((d) => {
        this.setData({ kind: 'barcode', big: d.big || '', sub: d.sub || '识别结果（演示）' });
        this.speak(d.big || '');
      })
      .catch(() => this.setData({ errMsg: '识别服务不可用' }));
  },

  // 名片 / 门头 OCR
  doOcr() {
    this.setData({ errMsg: '' });
    fetch(this.data.apiBase + '/api/ocr?kind=card')
      .then((r) => r.json())
      .then((d) => {
        this.setData({ kind: 'ocr', big: d.big || '', sub: d.sub || '' });
        this.speak(d.big || '');
      })
      .catch(() => this.setData({ errMsg: '识别服务不可用' }));
  },

  capture() {
    // 设备取帧：AIUI 运行时提供时启用；否则抛错由调用方回退
    if (typeof wx !== 'undefined' && wx.createCameraContext) {
      const ctx = wx.createCameraContext();
      return new Promise((resolve, reject) => {
        ctx.takePhoto({ quality: 'high', success: (r) => resolve(r.tempImagePath), fail: reject });
      });
    }
    throw new Error('camera API unavailable');
  },

  speak(t) {
    if (!t) return;
    try { speechSynthesis.speak(new SpeechSynthesisUtterance(t), 'enqueue'); } catch (e) {}
  },
};
</script>

<page>
  <view class="page">
    <text class="big">{{big}}</text>
    <text class="sub">{{sub}}</text>
    <text class="err" wx:if="{{errMsg}}">{{errMsg}}</text>
    <text class="go" bindtap="tapScan">▶ 识别条码/二维码</text>
    <text class="go2" bindtap="tapOcr">识别名片/门头</text>
    <text class="note">本产品不做人脸识别，只识别条码、名片与门头</text>
  </view>
</page>

<style>
.page { width: 100%; height: 100%; display: flex; flex-direction: column;
        justify-content: center; padding: 14px 18px; background: #000; color: #0f0; }
.big { font-size: 24px; font-weight: bold; line-height: 1.3; }
.sub { font-size: 12px; color: #4a4; margin-top: 4px; }
.err { font-size: 11px; color: #f66; margin-top: 4px; }
.go { font-size: 13px; border: 1px solid #0f0; border-radius: 6px;
      padding: 5px 10px; align-self: flex-start; margin-top: 8px; }
.go2 { font-size: 12px; color: #af9; margin-top: 6px; }
.note { font-size: 10px; color: #4a4; margin-top: 8px; }
</style>
