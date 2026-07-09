#!/usr/bin/perl
# Good News Bears — feed scraper + static site generator
# Zero dependencies beyond `curl` and core Perl (ships with macOS).
# Run:  perl generate.pl     (or ./refresh.sh)

use strict;
use warnings;
use utf8;               # this source file is UTF-8 (em dashes, etc. are real characters)
use POSIX qw(strftime);
use Time::Local qw(timegm);
use Encode ();

# ---- Good-news sources -----------------------------------------------------
# name | brand color | items to keep | feed URL | region | filter?
#   region  : US / UK / Global / Qatar  (shown as a flag on each card)
#   filter? : 1 = general-news feed, keep only uplifting stories (heuristic)
#             0 = dedicated good-news feed, keep everything
my @SOURCES = (
    ["Good News Network",      "#E8A13A", 12, "https://www.goodnewsnetwork.org/feed/",              "US",     0],
    ["Sunny Skyz",             "#F2777A", 10, "https://feeds.feedburner.com/SunnySkyz",             "US",     0],
    ["The Optimist Daily",     "#5AA9E6",  8, "https://www.optimistdaily.com/feed/",                "US",     0],
    ["Reasons to be Cheerful", "#8FBF6B",  8, "https://reasonstobecheerful.world/feed/",            "US",     0],
    ["Upworthy",               "#B57EDC",  8, "https://www.upworthy.com/rss.xml",                   "US",     0],
    ["Positive News",          "#3FA796",  8, "https://www.positive.news/feed/",                    "UK",     0],
    ["The Guardian",           "#C05640",  8, "https://www.theguardian.com/world/series/the-upside/rss", "UK", 0],
    ["BBC News",               "#66799E",  7, "https://feeds.bbci.co.uk/news/rss.xml",              "UK",     1],
    ["Al Jazeera",             "#C79A3C",  7, "https://www.aljazeera.com/xml/rss/all.xml",          "Qatar",  1],
    ["Euronews",               "#4C86C6",  7, "https://www.euronews.com/rss",                       "Global", 1],
    ["The New York Times",     "#4A4A4A",  6, "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", "US", 1],
    ["Los Angeles Times",      "#1F5C8B",  6, "https://www.latimes.com/local/rss2.0.xml",           "US",     1],
    ["The Seattle Times",      "#0E8A8A",  6, "https://www.seattletimes.com/feed/",                 "US",     1],
    ["NPR",                    "#5D3FD3",  6, "https://feeds.npr.org/1001/rss.xml",                 "US",     1],
    ["PBS NewsHour",           "#2A2D7C",  6, "https://www.pbs.org/newshour/feeds/rss/headlines",   "US",     1],
);

my $MAX_TOTAL = 96;    # cap on total cards
my $MAX_AGE   = 60;    # drop stories older than this many days (kills stale/evergreen feed items)
my $SHARE     = grep { $_ eq '--share' } @ARGV;   # --share => hosted/portable build (no remote images)
my $OUT       = $SHARE ? "share.html" : "index.html";
my $CUTOFF    = time() - $MAX_AGE * 24 * 3600;

# region -> flag emoji shown on each card
my %FLAG = (
    US     => "\x{1F1FA}\x{1F1F8}",
    UK     => "\x{1F1EC}\x{1F1E7}",
    Qatar  => "\x{1F1F6}\x{1F1E6}",
    Global => "\x{1F30D}",
);

# ---- positivity filter (for general-news feeds only) -----------------------
# We match WHOLE WORDS (not substrings) so "cat" never matches "cattle",
# "war" never matches "warm", "star" never matches "Starbucks", etc.

# Hard block-list: any of these in a headline disqualifies it outright.
my @NEG = qw(
  war wars warfare killed killing kills killer dead deadly death deaths dies died
  shot shooting shootings attack attacks attacked bomb bombing blast blasts missile
  terror terrorist murder murdered murdering manslaughter assault rape raped abuse
  abused crash crashed wounded injury injured injuries fracture fractured genocide
  famine protest protests protesters riot riots arrested arrest lawsuit sued suing
  guilty pleads convicted convict charged fraud scandal scandals corruption corrupt
  crisis collapse collapsed layoffs layoff recession tariff tariffs warns warning
  threat threats threatens threatening invasion hostage hostages casualties wildfire
  wildfires earthquake flood flooding flooded hurricane storm storms disaster
  disasters outbreak measles diabetes obesity cancer disease diseases virus covid
  opioid opioids addiction addicted deported deportation shutdown resign resigns
  resigned scam scams jailed jail prison violence violent clash clashes feud weapon
  weapons gun guns revolver rifle ammunition persecuted persecution trafficking
  trafficked tribute tributes migrant migrants immigrant immigrants immigration
  detention detained deportations heatwave sectarian court courts trial trials
  controversy controversial backlash boycott sanctions crackdown dispute disputes
  slam slams slammed fears toxic funeral funerals buried burial slain mourning
  mourners coffin casket obituary stabbed stabbing drowned drowning missing grief
  tragedy tragic victim victims evicted eviction cruelty seized defeat defeated
  banned spying indicted recall recalled destroy destroyed ruined fatal fatally
  wreck divorce trump biden senate congress democrat democrats republican
  republicans election elections nominee politician politics politicized lawmaker
  lawmakers governor campaign parliament president presidential minister ministers
  impeach ballot pentagon nato putin
);

# Positive signals (genuinely uplifting).
my @POS = qw(
  rescue rescued rescues saved save saves rescuers survivor survivors survives
  survived recover recovers recovered recovery cure cured cures heal heals healed
  hope hopeful kindness kind generous generosity donate donated donates donation
  donations charity charities volunteer volunteers volunteering hero heroes heroic
  reunite reunited reunion adopt adopted adoption restore restored restores revive
  revived thrive thriving milestone breakthrough breakthroughs discover discovered
  discovery celebrate celebrated celebrates celebration award awarded awards prize
  prizes winner winners wins won success successful uplifting heartwarming feelgood
  community comeback inspiring inspiration inspire inspired gift gifted gifts helps
  helping helped planted conservation wildlife protect protects protected renewable
  solar smiles smile joy joyful grateful gratitude cheer blossom blossoms rebuild
  rebuilt compassion
);

# Relaxed mode: also allow light, pleasant human-interest headlines.
my @LIGHT = qw(
  baby babies royal royals wedding weddings engagement puppy puppies kitten kittens
  panda pandas penguin penguins zoo festival festivals music song songs album
  concert concerts film movie movies painting paintings recipe recipes garden
  gardens museum museums anniversary birthday birthdays holiday couture mural murals
  orchestra symphony dance dancing marathon medal medals champion champions
  championship olympic olympics debut
);

my $NEG   = do { my $w = join('|', map { quotemeta } @NEG);   qr/\b(?:$w)\b/i };
my $POS   = do { my $w = join('|', map { quotemeta } @POS);   qr/\b(?:$w)\b/i };
my $LIGHT = do { my $w = join('|', map { quotemeta } @LIGHT); qr/\b(?:$w|world\s?cup)\b/i };

sub is_uplifting {
    my $text = shift // "";
    return 0 if $text =~ $NEG;                     # hard-news words disqualify outright
    return 1 if $text =~ $POS || $text =~ $LIGHT;  # positive OR light human-interest
    return 0;
}

# ---- helpers ---------------------------------------------------------------
sub strip_cdata { my $s = shift // ""; $s =~ s/<!\[CDATA\[(.*?)\]\]>/$1/gs; return $s; }

my %ENT = (
    amp=>'&', lt=>'<', gt=>'>', quot=>'"', apos=>"'", nbsp=>' ',
    hellip=>'...', mdash=>'-', ndash=>'-', rsquo=>"'", lsquo=>"'",
    rdquo=>'"', ldquo=>'"', eacute=>'e', 'amp;'=>'&',
);
sub decode_ent {
    my $s = shift // "";
    $s =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;
    $s =~ s/&#(\d+);/chr($1)/ge;
    $s =~ s/&([a-zA-Z]+);/exists $ENT{$1} ? $ENT{$1} : "&$1;"/ge;
    return $s;
}
# plain text: strip tags, decode entities, collapse whitespace
sub clean_text {
    my $s = strip_cdata(shift // "");
    $s =~ s/<[^>]+>/ /gs;      # drop tags
    $s = decode_ent($s);
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}
sub truncate_words {
    my ($s, $n) = @_;
    return $s if length($s) <= $n;
    my $cut = substr($s, 0, $n);
    $cut =~ s/\s+\S*$//;       # back off to a word boundary
    return "$cut\x{2026}";     # ellipsis
}
# escape for safe HTML output (we build plain text first, then escape)
sub esc {
    my $s = shift // "";
    $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

my %MON = (Jan=>0,Feb=>1,Mar=>2,Apr=>3,May=>4,Jun=>5,
           Jul=>6,Aug=>7,Sep=>8,Oct=>9,Nov=>10,Dec=>11);
# RFC-822 date -> epoch (best effort; unknown -> 0)
sub to_epoch {
    my $d = shift // "";
    if ($d =~ /(\d{1,2})\s+(\w{3})\w*\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|\w+)?/) {
        my ($day,$mon,$yr,$H,$M,$S,$tz) = ($1,$2,$3,$4,$5,$6//0,$7//"");
        return 0 unless exists $MON{$mon};
        my $e = eval { timegm($S,$M,$H,$day,$MON{$mon},$yr) };
        return 0 unless defined $e;
        if ($tz =~ /^([+-])(\d{2})(\d{2})$/) {
            my $off = ($2*3600 + $3*60) * ($1 eq '-' ? -1 : 1);
            $e -= $off;   # normalize to UTC
        }
        return $e;
    }
    return 0;
}
sub pretty_date {
    my $e = shift;
    return "" unless $e;
    return strftime("%b %-d, %Y", localtime($e));
}

# ---- fetch + parse ---------------------------------------------------------
my @items;
for my $src (@SOURCES) {
    my ($name, $color, $limit, $url, $region, $filter) = @$src;
    warn "Fetching $name ...\n";
    my $ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36";
    my $xml = qx{curl -sL --max-time 25 -A "$ua" "$url"};
    $xml = Encode::decode('UTF-8', $xml, Encode::FB_DEFAULT()) if $xml;
    unless ($xml && $xml =~ /<item[\s>]/i) {
        warn "  ! no items from $name (skipping)\n";
        next;
    }

    my $count = 0;
    while ($xml =~ /<item[\s>](.*?)<\/item>/sgi) {
        last if $count >= $limit;
        my $it = $1;

        my ($title) = $it =~ /<title[^>]*>(.*?)<\/title>/si;
        my ($link)  = $it =~ /<link[^>]*>(.*?)<\/link>/si;
        ($link)     = $it =~ /<guid[^>]*>(.*?)<\/guid>/si unless $link;
        my ($date)  = $it =~ /<pubDate[^>]*>(.*?)<\/pubDate>/si;
        ($date)     = $it =~ /<dc:date[^>]*>(.*?)<\/dc:date>/si unless $date;
        my ($body)  = $it =~ /<content:encoded[^>]*>(.*?)<\/content:encoded>/si;
        ($body)     = $it =~ /<description[^>]*>(.*?)<\/description>/si unless $body;

        # image: media tags, enclosure, or first <img> in the body
        my $img;
        ($img) = $it =~ /<media:content[^>]*url="([^"]+)"/i;
        ($img) = $it =~ /<media:thumbnail[^>]*url="([^"]+)"/i unless $img;
        ($img) = $it =~ /<enclosure[^>]*url="([^"]+)"[^>]*type="image/i unless $img;
        unless ($img) {
            my $raw = strip_cdata($body // "");
            ($img) = $raw =~ /<img[^>]+src="([^"]+)"/i;
        }

        $title = clean_text($title);
        next unless $title;
        $link  = clean_text($link);
        my $full    = clean_text($body);
        my $excerpt = truncate_words($full, 180);
        my $epoch   = to_epoch($date);

        # drop stale items from ANY feed (keeps the site feeling daily-fresh)
        next if $epoch && $epoch < $CUTOFF;
        # general-news feeds also need a parseable date + an uplifting headline
        next if $filter && (!$epoch || !is_uplifting($title));

        push @items, {
            source  => $name,
            color   => $color,
            region  => $region,
            flag    => ($FLAG{$region} // ""),
            title   => $title,
            link    => $link,
            excerpt => $excerpt,
            img     => ($img // ""),
            epoch   => $epoch,
            date    => pretty_date($epoch),
        };
        $count++;
    }
    warn "  + $count items\n";
}

@items = sort { $b->{epoch} <=> $a->{epoch} } @items;
@items = @items[0 .. ($MAX_TOTAL-1)] if @items > $MAX_TOTAL;
die "No items fetched — check your connection and try again.\n" unless @items;

# ---- render ----------------------------------------------------------------
my $updated = strftime("%A, %B %-d, %Y at %-I:%M %p", localtime);
my $year    = strftime("%Y", localtime);

# source filter pills
my %seen; my @order;
for my $s (@SOURCES) { push @order, $s unless $seen{$s->[0]}++; }
my $pills = qq{<button class="pill active" data-src="all">All good news</button>\n};
for my $s (@order) {
    my ($n,$c) = @$s;
    my $safe = esc($n);
    $pills .= qq{<button class="pill" data-src="$safe" style="--dot:$c">$safe</button>\n};
}

# cards
my $cards = "";
for my $i (@items) {
    my $t   = esc($i->{title});
    my $l   = esc($i->{link});
    my $ex  = esc($i->{excerpt});
    my $src = esc($i->{source});
    my $col = esc($i->{color});
    my $dt  = esc($i->{date});
    my $flag = $i->{flag};
    my $imghtml = ($i->{img} && !$SHARE)
        ? qq{<a class="thumb" href="$l" target="_blank" rel="noopener"><img src="}.esc($i->{img}).qq{" loading="lazy" alt=""></a>}
        : "";
    $cards .= <<"CARD";
<article class="card" data-src="$src">
  $imghtml
  <div class="body">
    <span class="badge" style="--c:$col">$src</span>
    <h2><a href="$l" target="_blank" rel="noopener">$t</a></h2>
    <p>$ex</p>
    <div class="meta">$flag&nbsp; $dt</div>
  </div>
</article>
CARD
}

my $count_txt = scalar(@items);

my $html = <<"HTML";
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Good News Bears \x{1F43B} — Daily Uplifting News</title>
<script>
  (function(){
    var t;
    try { t = localStorage.getItem('gnb-theme'); } catch(e){}
    document.documentElement.setAttribute('data-theme', t === 'light' ? 'light' : 'dark');
  })();
</script>
<style>
  :root, :root[data-theme="dark"]{
    --bg:#1c1917; --card:#262220; --ink:#F3ECE0; --soft:#B3A797;
    --line:#3a332e; --accent:#E8A13A; --accent-ink:#F2C572;
    --shadow:0 1px 2px rgba(0,0,0,.3), 0 8px 24px rgba(0,0,0,.35);
  }
  :root[data-theme="light"]{
    --bg:#FBF6EC; --card:#FFFFFF; --ink:#2C2621; --soft:#7A6F63;
    --line:#EFE6D6; --accent:#E8A13A; --accent-ink:#8a5a12;
    --shadow:0 1px 2px rgba(60,38,10,.05), 0 8px 24px rgba(60,38,10,.06);
  }
  *{box-sizing:border-box}
  body{
    margin:0; background:var(--bg); color:var(--ink);
    font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    -webkit-font-smoothing:antialiased;
  }
  a{color:inherit}
  .wrap{max-width:1180px; margin:0 auto; padding:0 22px}

  .theme-toggle{
    position:fixed; top:14px; right:16px; z-index:20;
    width:42px; height:42px; border-radius:50%;
    border:1px solid var(--line); background:var(--card); color:var(--ink);
    font-size:19px; line-height:1; cursor:pointer; box-shadow:var(--shadow);
    display:flex; align-items:center; justify-content:center;
    transition:transform .15s ease, border-color .15s ease;
  }
  .theme-toggle:hover{ transform:scale(1.08); border-color:var(--accent) }

  header.hero{ text-align:center; padding:44px 22px 20px }
  .logo{ font-size:60px; line-height:1; margin-bottom:2px }
  .sign-title{ margin:4px 0 2px }
  .sign-title svg{ width:min(430px,84vw); height:auto; display:block; margin:0 auto;
                   filter:drop-shadow(0 4px 8px rgba(0,0,0,.28)) }
  .visually-hidden{ position:absolute; width:1px; height:1px; padding:0; margin:-1px;
                    overflow:hidden; clip:rect(0 0 0 0); white-space:nowrap; border:0 }
  h1{ margin:0; font-size:clamp(30px,5vw,46px); letter-spacing:-.02em; font-weight:800 }
  .tagline{ margin:8px 0 0; color:var(--soft); font-size:17px }
  .updated{ margin:14px 0 0; font-size:13px; color:var(--soft) }
  .updated b{ color:var(--accent-ink); font-weight:600 }

  .filters{
    position:sticky; top:0; z-index:5; background:var(--bg);
    padding:16px 0; margin-top:8px;
    border-bottom:1px solid var(--line);
    display:flex; flex-wrap:wrap; gap:9px; justify-content:center;
  }
  .pill{
    font:inherit; font-size:14px; font-weight:600; cursor:pointer;
    border:1px solid var(--line); background:var(--card); color:var(--ink);
    padding:8px 15px; border-radius:999px; display:inline-flex; align-items:center; gap:7px;
    transition:.15s;
  }
  .pill::before{ content:""; width:9px; height:9px; border-radius:50%;
    background:var(--dot,var(--accent)); display:inline-block }
  .pill[data-src="all"]::before{ display:none }
  .pill:hover{ border-color:var(--accent) }
  .pill.active{ background:var(--accent); border-color:var(--accent); color:#3a2a08 }

  .grid{
    display:grid; gap:22px; padding:28px 0 10px;
    grid-template-columns:repeat(auto-fill, minmax(330px,1fr));
  }
  .card{
    background:var(--card); border:1px solid var(--line); border-radius:16px;
    overflow:hidden; box-shadow:var(--shadow); display:flex; flex-direction:column;
    transition:transform .15s ease, box-shadow .15s ease;
  }
  .card:hover{ transform:translateY(-3px);
    box-shadow:0 4px 10px rgba(60,38,10,.08), 0 16px 40px rgba(60,38,10,.12) }
  .thumb{ display:block; aspect-ratio:16/9; overflow:hidden; background:var(--line) }
  .thumb img{ width:100%; height:100%; object-fit:cover; display:block }
  .body{ padding:17px 19px 19px; display:flex; flex-direction:column; gap:9px; flex:1 }
  .badge{
    align-self:flex-start; font-size:11.5px; font-weight:700; letter-spacing:.03em;
    text-transform:uppercase; color:#fff; background:var(--c,var(--accent));
    padding:3px 9px; border-radius:6px;
  }
  .card h2{ margin:0; font-size:19px; line-height:1.34; letter-spacing:-.01em; font-weight:700 }
  .card h2 a{ text-decoration:none }
  .card h2 a:hover{ text-decoration:underline }
  .card p{ margin:0; color:var(--soft); font-size:14.5px; flex:1 }
  .meta{ font-size:12.5px; color:var(--soft); padding-top:4px; border-top:1px solid var(--line) }

  .empty{ text-align:center; color:var(--soft); padding:60px 0; display:none }

  footer{
    text-align:center; color:var(--soft); font-size:13.5px;
    padding:40px 22px 60px; margin-top:24px; border-top:1px solid var(--line);
  }
  footer a{ color:var(--accent-ink) }
  footer .src{ margin:10px 0 0 }
  code{ background:var(--line); padding:2px 6px; border-radius:5px; font-size:12px }
</style>
</head>
<body>
  <button id="themeToggle" class="theme-toggle" type="button" aria-label="Toggle light or dark theme"></button>
  <header class="hero">
    <div class="logo">\x{1F43B}</div>
    <h1 class="sign-title">
      <span class="visually-hidden">Good News Bears</span>
      <svg viewBox="0 0 480 200" role="img" aria-hidden="true" focusable="false">
        <rect x="96" y="118" width="18" height="74" rx="3" fill="#6B4A2E" stroke="#382415" stroke-width="2"/>
        <rect x="366" y="118" width="18" height="74" rx="3" fill="#6B4A2E" stroke="#382415" stroke-width="2"/>
        <rect x="28" y="24" width="424" height="128" rx="16" fill="#5A3A21" stroke="#382415" stroke-width="4"/>
        <rect x="44" y="40" width="392" height="96" rx="10" fill="none" stroke="#E9D9B0" stroke-width="2.5"/>
        <text x="240" y="88" text-anchor="middle" fill="#EBDCAF"
              font-family="Georgia,'Times New Roman',serif" font-weight="700" font-size="44" letter-spacing="1.5">GOOD NEWS</text>
        <text x="240" y="128" text-anchor="middle" fill="#EBDCAF"
              font-family="Georgia,'Times New Roman',serif" font-weight="700" font-style="italic" font-size="36">Bears</text>
      </svg>
    </h1>
    <p class="tagline">Your daily dose of uplifting news, gathered from around the world.</p>
    <p class="updated">Freshly gathered <b>$updated</b> &middot; $count_txt stories</p>
  </header>

  <nav class="filters wrap">
$pills  </nav>

  <main class="wrap">
    <div class="grid" id="grid">
$cards    </div>
    <p class="empty" id="empty">No stories from this source right now — try another. \x{1F43B}</p>
  </main>

  <footer>
    <p>Good News Bears pulls the latest feel-good stories from trusted U.S. sources.<br>
       Every headline links to the original article — please read &amp; share from the source.</p>
    <p class="src">Dedicated good-news: Good News Network &middot; Sunny Skyz &middot; The Optimist Daily &middot; Reasons to be Cheerful &middot; Upworthy &middot; Positive News &middot; The Guardian (The Upside)</p>
    <p class="src">Major outlets (filtered): The New York Times &middot; LA Times &middot; The Seattle Times &middot; NPR &middot; PBS NewsHour &middot; BBC &middot; Al Jazeera &middot; Euronews</p>
    <p style="font-size:12px">\x{1F30D} Major outlets are general-news feeds, filtered to surface only their uplifting &amp; light human-interest stories.</p>
    <p>To refresh with the newest stories, run <code>./refresh.sh</code> &middot; &copy; $year</p>
  </footer>

<script>
  const pills = document.querySelectorAll('.pill');
  const cards = document.querySelectorAll('.card');
  const empty = document.getElementById('empty');
  pills.forEach(p => p.addEventListener('click', () => {
    pills.forEach(x => x.classList.remove('active'));
    p.classList.add('active');
    const src = p.dataset.src; let shown = 0;
    cards.forEach(c => {
      const ok = (src === 'all' || c.dataset.src === src);
      c.style.display = ok ? '' : 'none';
      if (ok) shown++;
    });
    empty.style.display = shown ? 'none' : 'block';
  }));

  const root = document.documentElement;
  const tbtn = document.getElementById('themeToggle');
  function paintToggle(){
    tbtn.textContent = root.getAttribute('data-theme') === 'light' ? '\x{1F319}' : '\x{2600}\x{FE0F}';
  }
  tbtn.addEventListener('click', () => {
    const next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('gnb-theme', next); } catch(e){}
    paintToggle();
  });
  paintToggle();
</script>
</body>
</html>
HTML

# For the hosted/portable build, strip the outer document scaffolding so the
# markup drops cleanly into the Artifact host's own <html><head><body> wrapper.
if ($SHARE) {
    $html =~ s{<!doctype html>\s*}{}i;
    $html =~ s{</?html[^>]*>\s*}{}gi;
    $html =~ s{</?head[^>]*>\s*}{}gi;
    $html =~ s{</?body[^>]*>\s*}{}gi;
    $html =~ s{<meta[^>]*>\s*}{}gi;
}

open(my $fh, ">:encoding(UTF-8)", $OUT) or die "Cannot write $OUT: $!";
print $fh $html;
close($fh);
warn "\nWrote $OUT with $count_txt stories.\n";
