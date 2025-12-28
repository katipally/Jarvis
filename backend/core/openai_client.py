from openai import AsyncOpenAI
from core.config import settings
from core.logger import setup_logger
from typing import AsyncIterator, List, Dict, Any

logger = setup_logger(__name__)


class OpenAIClient:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        self.model = settings.OPENAI_MODEL
    
    async def stream_chat(
        self,
        messages: List[Dict[str, str]],
        tools: List[Dict[str, Any]] = None,
        include_reasoning: bool = True
    ) -> AsyncIterator[Dict[str, Any]]:
        """Stream chat responses from GPT-5-nano with reasoning support."""
        try:
            params = {
                "model": self.model,
                "messages": messages,
                "stream": True,
                "stream_options": {"include_usage": True}
            }
            
            if tools:
                params["tools"] = tools
                params["tool_choice"] = "auto"
            
            stream = await self.client.chat.completions.create(**params)
            
            async for chunk in stream:
                if not chunk.choices:
                    continue
                
                delta = chunk.choices[0].delta
                
                if delta.content:
                    yield {
                        "type": "content",
                        "content": delta.content
                    }
                
                if hasattr(delta, 'reasoning') and delta.reasoning:
                    yield {
                        "type": "reasoning",
                        "content": delta.reasoning
                    }
                
                if delta.tool_calls:
                    for tool_call in delta.tool_calls:
                        yield {
                            "type": "tool_call",
                            "tool_call": {
                                "id": tool_call.id,
                                "name": tool_call.function.name,
                                "arguments": tool_call.function.arguments
                            }
                        }
                
                if chunk.choices[0].finish_reason:
                    yield {
                        "type": "done",
                        "finish_reason": chunk.choices[0].finish_reason
                    }
        
        except Exception as e:
            logger.error(f"Error in stream_chat: {str(e)}")
            yield {
                "type": "error",
                "error": str(e)
            }
    
    async def get_embedding(self, text: str) -> List[float]:
        """Generate embedding for text."""
        try:
            response = await self.client.embeddings.create(
                model=settings.EMBEDDING_MODEL,
                input=text
            )
            return response.data[0].embedding
        except Exception as e:
            logger.error(f"Error generating embedding: {str(e)}")
            raise


openai_client = OpenAIClient()
