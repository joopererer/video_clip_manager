#!/usr/bin/env python3
"""
测试 ScrapeGraph-ai 是否能正常工作
"""

import os
import json
from scrapegraphai.graphs import SmartScraperGraph

def test_scrapegraph_ai():
    print("=== 测试 ScrapeGraph-ai ===")
    
    # 设置环境变量禁用遥测
    os.environ["SCRAPEGRAPHAI_TELEMETRY_ENABLED"] = "false"
    
    try:
        # 配置 LLM（使用本地 Ollama 模型，如果没有则使用 OpenAI）
        graph_config = {
            "llm": {
                "model": "ollama/llama3.2",  # 本地模型
                "model_tokens": 8192
            },
            "verbose": True,
            "headless": True,  # 无头模式
        }
        
        print("创建 SmartScraperGraph 实例...")
        
        # 创建 SmartScraperGraph 实例
        smart_scraper_graph = SmartScraperGraph(
            prompt="Extract video title, cover image URL, and description from this JAV video page. Return as JSON with fields: title, cover_url, description",
            source="https://missav.ws/fr/abw-182-uncensored-leak",
            config=graph_config
        )
        
        print("运行爬取任务...")
        
        # 运行爬取任务
        result = smart_scraper_graph.run()
        
        print("爬取结果:")
        print(json.dumps(result, indent=4, ensure_ascii=False))
        
        return result
        
    except Exception as e:
        print(f"❌ ScrapeGraph-ai 测试失败: {e}")
        
        # 尝试使用 OpenAI 模型
        try:
            print("尝试使用 OpenAI 模型...")
            
            # 检查是否有 OpenAI API Key
            openai_api_key = os.getenv("OPENAI_API_KEY")
            if not openai_api_key:
                print("❌ 未设置 OPENAI_API_KEY 环境变量")
                return None
            
            graph_config = {
                "llm": {
                    "api_key": openai_api_key,
                    "model": "openai/gpt-4o-mini",
                },
                "verbose": True,
                "headless": True,
            }
            
            smart_scraper_graph = SmartScraperGraph(
                prompt="Extract video title, cover image URL, and description from this JAV video page. Return as JSON with fields: title, cover_url, description",
                source="https://missav.ws/fr/abw-182-uncensored-leak",
                config=graph_config
            )
            
            result = smart_scraper_graph.run()
            
            print("OpenAI 爬取结果:")
            print(json.dumps(result, indent=4, ensure_ascii=False))
            
            return result
            
        except Exception as e2:
            print(f"❌ OpenAI 模型也失败: {e2}")
            return None

if __name__ == "__main__":
    test_scrapegraph_ai()
