from pathlib import Path
import json

root = Path(__file__).resolve().parent / 'plugin'
labels = {
    'Profiles': '分组', 'Import profile': '添加节点',
    'Source success': '订阅组已添加', 'Manual success': '单个节点已添加',
    'Manual node': '添加单个节点', 'Groups custom': '分组 · 自建组',
    'Ungrouped': '未分组', 'Ungrouped after move': '未分组 · 移动后',
    'Moved nodes': '主订阅 · 移动后', 'Moved backup': '备用订阅 · 移动后',
    'Move group': '移动到分组', 'Moved': '移动完成', 'New group': '新建分组',
    'Customgroup': '开发环境', 'Backup group': '备用订阅',
    'Backup connected': '备用订阅 · 已连接', 'Manual connected': 'HTTP · 已连接',
    'Local connected': 'SOCKS5 · 已连接', 'Custom connected': '开发环境 · 已连接',
    'Travel group': '旅行订阅', 'Travel connected': '旅行订阅 · 已连接',
    'Manual added nodes': '未分组 · 添加后', 'Quick switch': '切换分组',
    'Group': '分组', 'Group node': '组内节点', 'Protocol': '协议', 'back': '返回',
    'Group heading': '分组标题', 'Group identity': '分组信息',
    'Group current node': '分组当前节点', 'Group current identity': '当前节点信息',
    'Node identity': '节点信息', 'Node name': '节点名称', 'Node metadata': '节点详情',
    'Node protocol region': '协议与地区', 'Node actions': '节点操作',
    'Node row': '节点行', 'Node facts': '节点属性', 'Group toolbar': '分组工具栏',
    'Group list': '分组列表', 'Group current connection': '当前连接',
    'Current heading': '当前连接标题', 'Current facts': '当前连接属性',
    'Group workspace': '分组工作区', 'Group node toolbar': '组内节点工具栏',
    'Group node inventory': '组内节点列表', 'Selected group node': '组内当前节点',
    'Selected node protocol': '当前节点协议', 'Group node workspace': '组内节点工作区',
    'Simple add form': '添加表单', 'Single node address': '节点地址',
    'Subscription update': '订阅更新', 'Move node form': '移动节点表单',
    'Destination identity': '目标分组信息', 'Connection group hero': '连接主卡片',
    'Connection hero heading': '连接状态标题', 'Connection state': '连接状态',
    'Connection group summary': '当前分组概要', 'Connection group bottom': '连接卡片底栏',
    'Current connection facts': '连接信息', 'Network stats': '网络统计',
    'Connection trends': '网络趋势', 'Recent connection record': '最近连接记录',
    'Selected connection group': '当前连接分组', 'Selected group heading': '当前分组标题',
    'Selected group node': '当前分组节点', 'Mobile live speed': '移动端实时速度',
    'Today traffic simple': '今日流量', 'Simple visual chain': '可视化链路',
    'Simple chain actions': '链路操作', 'Visual chain workspace': '可视化链路工作区',
    'Persistent group status': '顶部连接状态', 'Persistent group speeds': '顶部实时速度',
    'Group flow steps': '分组流程步骤', 'Group components': '分组组件',
    'Grouped node components': '组内节点组件', 'Visual chain components': '链路组件',
    'Groups': '分组', 'Group latency trend': '分组延迟趋势', 'Latency chart heading': '延迟图表标题',
    'Latency time axis': '延迟时间轴', 'Group health': '分组健康状态', 'Health heading': '健康状态标题',
    'Health node identity': '节点健康信息', 'Fixed chain actions': '底部固定操作',
    'Chain reverse tested': '反向链路 · 测试通过', 'Chain reverse connected': '反向链路 · 已连接',
    'Source': '来源', 'Subscription': '订阅', 'Manual row': '手动节点行',
    'Chain': '代理链', 'Hop': '跳点', 'Summary': '概览', 'With source': '含分组标记',
}
for filename in ['zh-CN.json', 'zh-names.json']:
    p = root / filename
    data = json.loads(p.read_text(encoding='utf-8'))
    data.update(labels)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Group labels updated.')
