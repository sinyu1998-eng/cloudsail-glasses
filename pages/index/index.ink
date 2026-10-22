<script def>
{
  "navigationBarTitleText": "云帆现场助手"
}
</script>

<script setup>
export default {
  data: {
    tip: '按镜腿键或说指令进入',
    items: [
      { key: 'visit', label: '客户拜访' },
      { key: 'capacity', label: '产能/报价' },
      { key: 'translate', label: '实时翻译' },
      { key: 'notify', label: '消息推送' },
      { key: 'shop', label: '商城下单' },
      { key: 'profile', label: '客户档案' },
      { key: 'scan', label: '识别/显示' },
    ],
    focus: 0,
  },

  onKeyDown(event) {
    if (event.code === 'ArrowDown') {
      this.setData({ focus: (this.data.focus + 1) % this.data.items.length });
    } else if (event.code === 'ArrowUp') {
      this.setData({ focus: (this.data.focus + this.data.items.length - 1) % this.data.items.length });
    }
  },

  onKeyUp(event) {
    if (event.code === 'Enter') {
      const item = this.data.items[this.data.focus];
      window.open('pages/' + item.key + '/index', '_self');
    }
  },

  onVoiceWakeup(event) {
    const t = (event.keyword || '') + '';
    const map = [['拜访','visit'],['客户','visit'],['产能','capacity'],['报价','capacity'],
                 ['翻译','translate'],['推送','notify'],['消息','notify'],['商城','shop'],['下单','shop'],['档案','profile'],['风险','profile'],['识别','scan'],['扫码','scan']];
    for (const [k, key] of map) {
      if (t.indexOf(k) >= 0) { window.open('pages/' + key + '/index', '_self'); return; }
    }
  },

  tapItem(event) {
    window.open('pages/' + event.target.dataset.key + '/index', '_self');
  },
};
</script>

<page>
  <view class="page">
    <text class="title">云帆现场助手</text>
    <view class="menu">
      <view
        wx:for="{{items}}"
        wx:key="key"
        class="item {{focus === index ? 'on' : ''}}"
        data-key="{{item.key}}"
        bindtap="tapItem"
      >
        <text>{{item.label}}</text>
      </view>
    </view>
    <text class="tip">{{tip}}</text>
  </view>
</page>

<style>
.page {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 16px 20px;
  background: #000;
  color: #0f0;
}
.title {
  font-size: 20px;
  font-weight: bold;
  margin-bottom: 12px;
}
.menu { display: flex; flex-direction: column; }
.item {
  padding: 8px 12px;
  border: 1px solid #0f0;
  border-radius: 6px;
  margin-bottom: 8px;
  font-size: 15px;
}
.item.on { background: #0f0; color: #000; }
.tip { font-size: 11px; color: #4a4; margin-top: 4px; }
</style>
