"""Generates docs/architecture.drawio for the Self-Service Digital Assistant project using drawpyo.

Run with: python3 scripts/generate_diagram.py
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)


def aws_style(icon_name, fill_color):
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_group(page, name, x, y, width, height):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "rounded=0;whiteSpace=wrap;html=1;dashed=1;dashPattern=8 4;fillColor=none;"
        "strokeColor=#01A88D;verticalAlign=top;align=center;fontColor=#01A88D;fontSize=11;"
    )
    return group


def add_edge(page, source, target, label=None, bidirectional=False):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "block" if bidirectional else "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Self-Service Digital Assistant"

    user = add_node(page, "User", 40, 200, "client", "#232F3E")
    chat_ui = add_node(page, "GenAI Chat UI", 220, 200, "client", "#232F3E")
    chatbot = add_node(page, "AI Chatbot\n(QnAIntent)", 420, 200, "lambda_function", "#ED7100")

    group = add_group(page, "", 600, 150, 260, 420)
    foundation_models = add_node(page, "Access foundation\nmodels", 640, 190, "machine_learning", "#01A88D")
    private_data = add_node(page, "Company's relevant\nprivate data", 640, 350, "machine_learning", "#01A88D")

    web_delivery = add_node(page, "Web content\ndelivery", 220, 360, "cloudfront", "#8C4FFF")
    web_assets = add_node(page, "Web UI assets\n(objects)", 220, 500, "bucket", "#7AA116")

    document_store = add_node(page, "Document store\n(objects)", 640, 520, "bucket", "#7AA116")

    add_edge(page, user, chat_ui, "User input prompt / Response", bidirectional=True)
    add_edge(page, chat_ui, chatbot, "User intent / Answer", bidirectional=True)
    add_edge(page, chatbot, foundation_models, bidirectional=True)

    add_edge(page, chat_ui, web_delivery)
    add_edge(page, web_delivery, web_assets)

    add_edge(page, foundation_models, private_data, bidirectional=True)
    add_edge(page, private_data, document_store, "Search / Context", bidirectional=True)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
