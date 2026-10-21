<script def>
{
  "navigationBarTitleText": "线上商城"
}
</script>

<script setup>
// 语音下单：展示商品 → 说"买两件保温杯" → 后端匹配商品与数量 → 生成订单
// 数字由后端确定性匹配，价格不出错
export default {
  data: {
    apiBase: 'http://192.168.1.100:8000',
    products: [],
    heard: '',
    order: null,
    err: '',
  },
  session: null,

  onReady() { this.load(); },
  onUnload() { if (this.session) { try { this.session.abort(); } catch (e) {} } },

  load() {
    fetch(this.data.apiBase + '/api/products')
      .then((r) => r.json())
      .then((d) => this.setData({ products: d.products || [] }))
      .catch(() => this.setData({ err: '连不上商城后端' }));
  },

  onKeyDown(event) {
    if (event.code === 'Enter' && !this.session) this.startListen();
  },
  tapStart() { if (!this.session) this.startListen(); },

  startListen() {
    this.setData({ heard: '', order: null, err: '' });
    const rec = new SpeechRecognition();
    this.session = rec;
    rec.lang = 'zh-CN';
    rec.onresult = (event) => {
      const res = event.results;
      if (!res || !res.length) return;
      const last = res[res.length - 1];
      const text = (last && last[0] && last[0].transcript) || '';
      if (!text) return;
      this.setData({ heard: text });
      this.order(text);
    };
    rec.onerror = (event) => this.setData({ err: '识别失败：' + (event.error || '') });
    rec.onend = () => { this.session = null; };
    try { rec.start(); } catch (e) { this.setData({ err: '无法启动麦克风' }); }
  },

  order(text) {
    fetch(this.data.apiBase + '/api/orders', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    })
      .then((r) => r.json())
      .then((d) => {
        if (d.ok) this.setData({ order: d });
        else this.setData({ err: d.msg || '没听懂要买什么' });
      })
      .catch(() => this.setData({ err: '下单失败，稍后重试' }));
  },

  stateText(s) {
    return { idle: '按确认键开始说中文', listening: '请说…', translating: '翻译中…',
             done: '已朗读英文', error: '出错了' }[s] || '';
  },
};
</script>

<page>
  <view class="page">
    <text class="title">线上商城 · 语音下单</text>
    <view class="list">
      <text class="p" wx:for="{{products}}" wx:key="sku">{{index + 1}}. {{item.name}}  ¥{{item.price}}</text>
    </view>
    <text class="heard" wx:if="{{heard}}">「{{heard}}」</text>
    <block wx:if="{{order}}">
      <text class="ok">已下单：{{order.name}} × {{order.qty}} = ¥{{order.total}}</text>
      <text class="ok2">订单号 {{order.orderId}} ｜ 稍后推送发货通知</text>
    </block>
    <text class="err" wx:if="{{err}}">{{err}}</text>
    <text class="go" bindtap="tapStart">▶ 说"买两件保温杯"</text>
  </view>
</page>

<style>
.page { width: 100%; height: 100%; display: flex; flex-direction: column;
        padding: 12px 18px; background: #000; color: #0f0; }
.title { font-size: 16px; font-weight: bold; margin-bottom: 6px; }
.list { display: flex; flex-direction: column; margin-bottom: 6px; }
.p { font-size: 12px; line-height: 1.6; color: #af9; }
.heard { font-size: 12px; color: #7f7; margin: 4px 0; }
.ok { font-size: 13px; color: #0f0; font-weight: bold; }
.ok2 { font-size: 11px; color: #4a4; margin-top: 2px; }
.err { font-size: 11px; color: #f66; }
.go { font-size: 12px; border: 1px solid #0f0; border-radius: 6px;
      padding: 5px 10px; align-self: flex-start; margin-top: 6px; }
</style>
