<script def>
{
  "navigationBarTitleText": "消息推送"
}
</script>

<script setup>
// 老板/总部推送 → 眼镜接收：每 8 秒拉一次未读消息，显示并朗读
// Demo 里从后端 /docs 或 curl POST /api/notifications 即可"推一条"
export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',
    msgs: [],
    lastId: 0,
    timer: null,
  },

  onReady() { this.poll(); this.start(); },
  onHide() { this.stop(); },
  onShow() { this.start(); },
  onUnload() { this.stop(); },

  start() {
    if (this.data.timer) return;
    this.data.timer = setInterval(() => this.poll(), 8000);
  },
  stop() {
    if (this.data.timer) { clearInterval(this.data.timer); this.data.timer = null; }
  },

  poll() {
    fetch(this.data.apiBase + '/api/notifications?after=' + this.data.lastId)
      .then((r) => r.json())
      .then((d) => {
        if (!d.msgs || !d.msgs.length) return;
        const box = this.data.msgs.slice(-4);
        d.msgs.forEach((m) => {
          box.push({ id: m.id, from: m.from, text: m.text });
          this.setData({ lastId: Math.max(this.data.lastId, m.id) });
          try { speechSynthesis.speak(new SpeechSynthesisUtterance(m.text), 'enqueue'); } catch (e) {}
        });
        this.setData({ msgs: box });
      })
      .catch(() => {});
  },

  tapClear() { this.setData({ msgs: [] }); },
};
</script>

<page>
  <view class="page">
    <text class="title">推送消息</text>
    <block wx:if="{{msgs.length === 0}}">
      <text class="empty">等待推送…（电脑访问 :8000/docs 可发一条）</text>
    </block>
    <view class="list">
      <view class="msg" wx:for="{{msgs}}" wx:key="id">
        <text class="from">{{item.from}}</text>
        <text class="text">{{item.text}}</text>
      </view>
    </view>
    <text class="go" bindtap="tapClear">清屏</text>
  </view>
</page>

<style>
.page { width: 100%; height: 100%; display: flex; flex-direction: column;
        padding: 12px 18px; background: #000; color: #0f0; }
.title { font-size: 16px; font-weight: bold; margin-bottom: 6px; }
.empty { font-size: 11px; color: #4a4; }
.list { display: flex; flex-direction: column; }
.msg { border-left: 2px solid #0f0; padding: 3px 0 3px 8px; margin-bottom: 6px; }
.from { font-size: 11px; color: #4a4; }
.text { font-size: 13px; line-height: 1.4; color: #af9; }
.go { font-size: 12px; border: 1px solid #0f0; border-radius: 6px;
      padding: 4px 10px; align-self: flex-start; margin-top: 4px; }
</style>
