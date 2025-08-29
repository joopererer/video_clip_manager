#!/usr/bin/env python3
import sys
import json
import cloudscraper

def test_missav_access(url):
    """测试使用 cloudscraper 访问 MissAV"""
    try:
        print(f"正在使用 cloudscraper 访问: {url}")
        
        # 创建 cloudscraper 实例
        scraper = cloudscraper.create_scraper(
            browser={
                'browser': 'chrome',
                'platform': 'windows',
                'desktop': True
            }
        )
        
        # 发送请求
        response = scraper.get(url)
        
        print(f"状态码: {response.status_code}")
        print(f"响应头: {dict(response.headers)}")
        
        if response.status_code == 200:
            print("✅ 成功绕过 Cloudflare!")
            content = response.text
            print(f"内容长度: {len(content)}")
            
            # 尝试提取标题
            import re
            title_patterns = [
                r'<meta[^>]*property="og:title"[^>]*content="([^"]+)"',
                r'<meta[^>]*name="twitter:title"[^>]*content="([^"]+)"',
                r'<h1[^>]*class="[^"]*title[^"]*"[^>]*>([^<]+)</h1>',
                r'<h1[^>]*>([^<]+)</h1>',
                r'<title[^>]*>([^<]+)</title>',
            ]
            
            for i, pattern in enumerate(title_patterns):
                match = re.search(pattern, content, re.IGNORECASE)
                if match:
                    title = match.group(1).strip()
                    if title:
                        print(f"找到标题 (模式 {i}): {title}")
                        break
            
            if len(content) > 200:
                print(f"内容预览: {content[:200]}...")
                
            return {
                'success': True,
                'status_code': response.status_code,
                'content': content,
                'content_length': len(content)
            }
        else:
            print(f"❌ 失败，状态码: {response.status_code}")
            print(f"错误内容: {response.text[:500]}...")
            return {
                'success': False,
                'status_code': response.status_code,
                'error': response.text[:500]
            }
            
    except Exception as e:
        print(f"❌ 请求错误: {e}")
        return {
            'success': False,
            'error': str(e)
        }

if __name__ == "__main__":
    if len(sys.argv) > 1:
        url = sys.argv[1]
    else:
        url = "https://missav.ws/fr/abw-126-uncensored-leak"
    
    result = test_missav_access(url)
    
    # 输出 JSON 格式结果供 Dart 解析
    print("\n=== JSON RESULT ===")
    print(json.dumps(result, ensure_ascii=False, indent=2))
