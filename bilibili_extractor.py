#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Bilibili视频信息提取脚本
用于从Bilibili视频URL中提取视频信息
"""

import sys
import json
import re
import requests
from urllib.parse import urlparse, parse_qs

def extract_bvid_from_url(url):
    """从URL中提取BV号"""
    # 匹配BV开头的视频ID
    bv_match = re.search(r'BV[a-zA-Z0-9]+', url)
    if bv_match:
        return bv_match.group()
    
    # 匹配av开头的视频ID
    av_match = re.search(r'av(\d+)', url)
    if av_match:
        return f"av{av_match.group(1)}"
    
    return None

def get_video_info(bvid):
    """获取视频信息"""
    try:
        # 使用Bilibili API获取视频信息
        api_url = f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.bilibili.com/'
        }
        
        response = requests.get(api_url, headers=headers, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        
        if data['code'] == 0:
            video_data = data['data']
            
            # 提取视频信息，确保数值类型正确
            duration = video_data.get('duration', 0)
            if isinstance(duration, (int, float)):
                duration_ms = int(duration * 1000)  # 转换为毫秒
            else:
                duration_ms = 0

            # 处理统计数据的数值类型
            stat = video_data.get('stat', {})
            def safe_int(value):
                if isinstance(value, (int, float)):
                    return int(value)
                return 0

            video_info = {
                'id': video_data.get('bvid', bvid),
                'title': video_data.get('title', ''),
                'description': video_data.get('desc', ''),
                'duration': duration_ms,
                'thumbnail_url': video_data.get('pic', ''),
                'platform': 'bilibili',
                'metadata': {
                    'aid': video_data.get('aid'),
                    'cid': video_data.get('cid'),
                    'owner': video_data.get('owner', {}).get('name', ''),
                    'view_count': safe_int(stat.get('view', 0)),
                    'danmaku_count': safe_int(stat.get('danmaku', 0)),
                    'reply_count': safe_int(stat.get('reply', 0)),
                    'favorite_count': safe_int(stat.get('favorite', 0)),
                    'coin_count': safe_int(stat.get('coin', 0)),
                    'share_count': safe_int(stat.get('share', 0)),
                    'like_count': safe_int(stat.get('like', 0)),
                }
            }
            
            return video_info
        else:
            raise Exception(f"API返回错误: {data.get('message', '未知错误')}")
            
    except requests.exceptions.RequestException as e:
        raise Exception(f"网络请求失败: {str(e)}")
    except json.JSONDecodeError as e:
        raise Exception(f"JSON解析失败: {str(e)}")
    except Exception as e:
        raise Exception(f"获取视频信息失败: {str(e)}")

def main():
    """主函数"""
    if len(sys.argv) != 2:
        print("用法: python bilibili_extractor.py <bilibili_url>")
        sys.exit(1)
    
    url = sys.argv[1]
    
    try:
        # 从URL中提取BV号
        bvid = extract_bvid_from_url(url)
        if not bvid:
            raise Exception("无法从URL中提取视频ID")
        
        # 获取视频信息
        video_info = get_video_info(bvid)
        
        # 输出JSON格式的视频信息，使用UTF-8编码
        import sys
        if sys.platform.startswith('win'):
            # Windows系统使用UTF-8编码输出
            import codecs
            sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
        
        print(json.dumps(video_info, ensure_ascii=False, indent=2))
        
    except Exception as e:
        print(f"错误: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
