"""
Applet: RSS Reader (with Hebrew RTL)
Summary: RSS Feed Reader
Description: Displays entries from an RSS feed URL. Hebrew text is rendered RTL.
Author: Daniel Sitnik, modified by ChatGPT
"""

load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("xpath.star", "xpath")

# cache data for 15 minutes
CACHE_TTL_SECONDS = 900

DEFAULT_FEED_URL = "https://discuss.tidbyt.com/latest.rss"
DEFAULT_ARTICLE_COUNT = 3
DEFAULT_FEED_NAME = "Tidbyt Forums"
DEFAULT_TITLE_COLOR = "#db7e35"
DEFAULT_TITLE_BG_COLOR = "#333333"
DEFAULT_ARTICLE_COLOR = "#65d1e6"
DEFAULT_SHOW_CONTENT = False
DEFAULT_CONTENT_COLOR = "#ff8c00"
DEFAULT_FONT = "tom-thumb"

# ------------------------------------------------------------
# Hebrew detection + helper
# ------------------------------------------------------------

def is_hebrew(text):
    """
    Return True if text contains any Hebrew characters.
    Hebrew ranges: 0x0590-0x05FF, 0xFB1D-0xFB4F
    """
    for ch in text:
        code = ord(ch)
        if (code >= 0x0590 and code <= 0x05FF) or (code >= 0xFB1D and code <= 0xFB4F):
            return True
    return False


def make_wrapped_text(text, color, font, debug_hebrew):
    """
    Builds a WrappedText element that:
    - Right-aligns if text is Hebrew
    - Left-aligns otherwise
    - If debug_hebrew is True, prefixes detected Hebrew with ↔
    """
    t = text.strip()
    heb = is_hebrew(t)

    if debug_hebrew and heb:
        # Visual marker that this line was detected as Hebrew
        t = "↔ " + t

    align = "right" if heb else "left"

    return render.WrappedText(
        t,
        color = color,
        font = font,
        width = 64,      # full Tidbyt width so right-align is meaningful
        align = align,
    )

# ------------------------------------------------------------
# RSS fetching
# ------------------------------------------------------------

def get_feed(url, article_count):
    """
    Retrieve and parse the RSS feed.

    Args:
        url (str): The RSS feed URL.
        article_count (int): The number of articles to retrieve.

    Returns:
        list: List of (title, content) tuples.
    """

    res = http.get(url = url, ttl_seconds = CACHE_TTL_SECONDS)
    if res.status_code != 200:
        fail("Request to %s failed with status code: %d: %s" % (url, res.status_code, res.body()))

    articles = []

    data_xml = xpath.loads(res.body())

    # Try RSS 2.0 path: /rss/channel/item
    items = xpath.query(data_xml, "/rss/channel/item")
    if len(items) == 0:
        # Try Atom: /feed/entry
        items = xpath.query(data_xml, "/feed/entry")

    # Just in case there are fewer items than requested
    max_count = min(article_count, len(items))

    for i in range(0, max_count):
        # For RSS items, title/description; for Atom, title/summary/content
        # Use xpath on each item node
        item = items[i]

        title_nodes = xpath.query(item, "title/text()")
        if len(title_nodes) == 0:
            title_nodes = ["(no title)"]
        title = title_nodes[0]

        # Prefer description or summary, fallback to content
        desc_nodes = xpath.query(item, "description/text()")
        if len(desc_nodes) == 0:
            desc_nodes = xpath.query(item, "summary/text()")
        if len(desc_nodes) == 0:
            desc_nodes = xpath.query(item, "content/text()")
        if len(desc_nodes) == 0:
            desc_nodes = [""]

        content = desc_nodes[0]

        articles.append((title, content))

    return articles

# ------------------------------------------------------------
# Rendering
# ------------------------------------------------------------

def render_articles(articles, show_content, article_color, content_color, font, debug_hebrew):
    """
    Build the list of renderable children for all articles.
    """
    children = []

    for article in articles:
        title = article[0]
        content = article[1]

        # Article title (RTL if Hebrew)
        children.append(
            make_wrapped_text(title, article_color, font, debug_hebrew)
        )

        # Optional article content
        if show_content and content != "":
            children.append(
                make_wrapped_text(content, content_color, font, debug_hebrew)
            )

        # Spacer between articles
        children.append(
            render.Box(width = 64, height = 8, color = "#000000")
        )

    return children

# ------------------------------------------------------------
# Main applet entrypoint
# ------------------------------------------------------------

def main(config):
    # Read configuration
    feed_url = config.get("feed_url", DEFAULT_FEED_URL)
    feed_name = config.get("feed_name", DEFAULT_FEED_NAME)

    article_count = config.get("article_count", DEFAULT_ARTICLE_COUNT)
    # Ensure int
    if type(article_count) == "string":
        article_count = int(article_count)

    title_color = config.get("title_color", DEFAULT_TITLE_COLOR)
    title_bg_color = config.get("title_bg_color", DEFAULT_TITLE_BG_COLOR)
    article_color = config.get("article_color", DEFAULT_ARTICLE_COLOR)
    show_content = config.get("show_content", DEFAULT_SHOW_CONTENT)
    content_color = config.get("content_color", DEFAULT_CONTENT_COLOR)
    font = config.get("font", DEFAULT_FONT)
    debug_hebrew = config.get("debug_hebrew", False)

    # Get feed articles
    articles = get_feed(feed_url, article_count)

    # Header text: right-align if Hebrew feed name
    feed_name_is_hebrew = is_hebrew(feed_name)
    header_align = "right" if feed_name_is_hebrew else "left"
    header_text = feed_name

    if debug_hebrew and feed_name_is_hebrew:
        header_text = "↔ " + header_text

    return render.Root(
        delay = 100,
        show_full_animation = True,
        child = render.Column(
            children = [
                # Feed name banner
                render.Box(
                    width = 64,
                    height = 8,
                    color = title_bg_color,
                    child = render.Text(
                        header_text,
                        color = title_color,
                        font = "tom-thumb",
                        align = header_align,
                    ),
                ),
                # Vertical-scrolling article list
                render.Marquee(
                    height = 24,
                    scroll_direction = "vertical",
                    offset_start = 24,
                    child = render.Column(
                        main_align = "space_between",
                        children = render_articles(
                            articles,
                            show_content,
                            article_color,
                            content_color,
                            font,
                            debug_hebrew,
                        ),
                    ),
                ),
            ],
        ),
    )

# ------------------------------------------------------------
# Configuration schema
# ------------------------------------------------------------

def schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.String(
                id = "feed_url",
                name = "Feed URL",
                desc = "The RSS or Atom feed URL to read.",
                icon = "link",
                default = DEFAULT_FEED_URL,
            ),
            schema.String(
                id = "feed_name",
                name = "Feed Name",
                desc = "Display name for the RSS feed.",
                icon = "text_fields",
                default = DEFAULT_FEED_NAME,
            ),
            schema.Int(
                id = "article_count",
                name = "Article Count",
                desc = "Number of recent articles to display.",
                icon = "format_list_numbered",
                default = DEFAULT_ARTICLE_COUNT,
            ),
            schema.Bool(
                id = "show_content",
                name = "Show Article Content",
                desc = "If enabled, shows article summary/content under the title.",
                icon = "subject",
                default = DEFAULT_SHOW_CONTENT,
            ),
            schema.String(
                id = "font",
                name = "Font",
                desc = "Font to use for article text.",
                icon = "font_download",
                default = DEFAULT_FONT,
                options = [
                    schema.Option(id = "tom-thumb", name = "tom-thumb"),
                    schema.Option(id = "6x13", name = "6x13"),
                ],
            ),
            schema.Bool(
                id = "debug_hebrew",
                name = "Debug Hebrew Detection",
                desc = "Prefix detected Hebrew text with ↔ so you can verify RTL detection.",
                icon = "bug_report",
                default = False,
            ),
            schema.Color(
                id = "title_color",
                name = "Feed Name Color",
                desc = "The color of the RSS feed name.",
                icon = "brush",
                default = DEFAULT_TITLE_COLOR,
            ),
            schema.Color(
                id = "title_bg_color",
                name = "Feed Name Background",
                desc = "The color of the RSS feed name background.",
                icon = "brush",
                default = DEFAULT_TITLE_BG_COLOR,
            ),
            schema.Color(
                id = "article_color",
                name = "Article Title Color",
                desc = "The color of the article's title.",
                icon = "brush",
                default = DEFAULT_ARTICLE_COLOR,
            ),
            schema.Color(
                id = "content_color",
                name = "Article Content Color",
                desc = "The color of the article's content.",
                icon = "brush",
                default = DEFAULT_CONTENT_COLOR,
            ),
        ],
    )
