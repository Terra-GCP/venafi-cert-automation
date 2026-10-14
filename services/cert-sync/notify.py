from __future__ import annotations

import json

from google.cloud import pubsub_v1


def publish_result(project_id: str, topic: str, payload: dict) -> None:
    if not topic:
        return
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic)
    publisher.publish(topic_path, json.dumps(payload).encode("utf-8")).result(timeout=30)
