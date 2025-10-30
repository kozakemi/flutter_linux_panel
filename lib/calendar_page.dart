import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  final DateTime _today = DateTime.now();

  // 获取当前月份的天数
  int _getDaysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  // 获取当月第一天是星期几
  int _getFirstDayOfWeek(int year, int month) {
    return DateTime(year, month, 1).weekday % 7;
  }

  // 计算与今天的时间间隔
  String _getTimeFromToday() {
    final difference = _selectedDate.difference(_today);
    final days = difference.inDays;

    if (days == 0) {
      return '今天';
    } else if (days > 0) {
      return '$days天后';
    } else {
      return '${-days}天前';
    }
  }

  // 构建日历头部
  Widget _buildCalendarHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _focusedDate =
                    DateTime(_focusedDate.year, _focusedDate.month - 1, 1);
              });
            },
          ),
          GestureDetector(
            onTap: () => _showDatePicker(),
            child: Text(
              DateFormat('yyyy年MM月').format(_focusedDate),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _focusedDate =
                    DateTime(_focusedDate.year, _focusedDate.month + 1, 1);
              });
            },
          ),
        ],
      ),
    );
  }

  // 显示年月选择器
  void _showDatePicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Text('选择年月',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {});
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  children: [
                    // 年份选择器
                    Expanded(
                      child: CupertinoPicker(
                        itemExtent: 40,
                        onSelectedItemChanged: (int index) {
                          setState(() {
                            _focusedDate = DateTime(_today.year - 10 + index,
                                _focusedDate.month, 1);
                          });
                        },
                        scrollController: FixedExtentScrollController(
                          initialItem: 10, // 默认选中当前年
                        ),
                        children: List<Widget>.generate(21, (int index) {
                          return Center(
                            child: Text(
                              '${_today.year - 10 + index}年',
                              style: const TextStyle(fontSize: 16),
                            ),
                          );
                        }),
                      ),
                    ),
                    // 月份选择器
                    Expanded(
                      child: CupertinoPicker(
                        itemExtent: 40,
                        onSelectedItemChanged: (int index) {
                          setState(() {
                            _focusedDate =
                                DateTime(_focusedDate.year, index + 1, 1);
                          });
                        },
                        scrollController: FixedExtentScrollController(
                          initialItem: _focusedDate.month - 1,
                        ),
                        children: List<Widget>.generate(12, (int index) {
                          return Center(
                            child: Text(
                              '${index + 1}月',
                              style: const TextStyle(fontSize: 16),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 构建星期标题
  Widget _buildWeekdayNames() {
    final weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: weekdays
          .map((day) => Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ))
          .toList(),
    );
  }

  // 构建日历网格
  Widget _buildCalendarGrid() {
    final daysInMonth = _getDaysInMonth(_focusedDate.year, _focusedDate.month);
    final firstDayOfWeek =
        _getFirstDayOfWeek(_focusedDate.year, _focusedDate.month);

    // 计算行数
    final rowCount = ((daysInMonth + firstDayOfWeek) / 7).ceil();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.5, // 进一步调整比例减少高度
        mainAxisSpacing: 1, // 进一步减少垂直间距
        crossAxisSpacing: 1, // 进一步减少水平间距
      ),
      itemCount: rowCount * 7,
      itemBuilder: (context, index) {
        // 计算日期
        final dayNumber = index + 1 - firstDayOfWeek;

        // 检查是否在当前月份范围内
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox.shrink();
        }

        // 创建日期对象
        final date = DateTime(_focusedDate.year, _focusedDate.month, dayNumber);

        // 检查是否是今天
        final isToday = _today.year == date.year &&
            _today.month == date.month &&
            _today.day == date.day;

        // 检查是否是选中日期
        final isSelected = _selectedDate.year == date.year &&
            _selectedDate.month == date.month &&
            _selectedDate.day == date.day;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = date;
            });
          },
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blue
                  : (isToday ? Colors.blue.withOpacity(0.2) : null),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                dayNumber.toString(),
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isToday ? Colors.blue : null),
                  fontWeight: isSelected || isToday ? FontWeight.bold : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 构建选中日期的详细信息
  Widget _buildSelectedDateDetails() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧日期信息
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '选中: ${DateFormat('yyyy年MM月dd日').format(_selectedDate)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '星期${[
                    '日',
                    '一',
                    '二',
                    '三',
                    '四',
                    '五',
                    '六'
                  ][_selectedDate.weekday % 7]}',
                  style: const TextStyle(fontSize: 13),
                ),
                // const SizedBox(height: 4),
                // const Text('今日事项:', style: TextStyle(fontSize: 13)),
                // const Text('暂无事项', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          // 右侧时间间隔信息
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('与今天相距', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getTimeFromToday(),
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取设备尺寸
    final size = MediaQuery.of(context).size;
    final isWideScreen = size.width > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('日历'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _selectedDate = _today;
                _focusedDate = _today;
              });
            },
            tooltip: '回到今天',
          ),
        ],
      ),
      body: isWideScreen
          // 宽屏设备使用左右布局
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧日历部分
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCalendarHeader(),
                        const Divider(height: 1),
                        _buildWeekdayNames(),
                        const SizedBox(height: 4),
                        _buildCalendarGrid(),
                      ],
                    ),
                  ),
                ),
                // 右侧时间间隔计算部分
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: _buildTimeIntervalDetails(),
                  ),
                ),
              ],
            )
          // 窄屏设备使用上下布局
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min, // 设置为min以避免占用过多空间
                children: [
                  _buildCalendarHeader(),
                  const Divider(height: 1),
                  _buildWeekdayNames(),
                  const SizedBox(height: 2),
                  _buildCalendarGrid(),
                  _buildSelectedDateDetails(),
                ],
              ),
            ),
    );
  }

  // 构建时间间隔详情（用于宽屏设备右侧显示）
  Widget _buildTimeIntervalDetails() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选中日期详情',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            DateFormat('yyyy年MM月dd日').format(_selectedDate),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '星期${[
              '日',
              '一',
              '二',
              '三',
              '四',
              '五',
              '六'
            ][_selectedDate.weekday % 7]}',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          const Text('与今天的时间间隔:', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _getTimeFromToday(),
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // const SizedBox(height: 24),
          // const Text('今日事项:', style: TextStyle(fontSize: 16)),
          // const SizedBox(height: 8),
          // const Text('暂无事项', style: TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
