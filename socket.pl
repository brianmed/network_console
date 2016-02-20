#!/opt/perl

use Mojolicious::Lite;

get '/' => sub {
    my $c = shift;

    $c->render(template => 'index');
};

websocket 'connect' => sub {
    my $c = shift;

    $c->app->log->debug('WebSocket opened');

    $c->inactivity_timeout(1800);

    $c->on(message => sub {
        my ($c, $msg) = @_;

        if ($msg =~ m/^connect\s+(?<host>\S+)\s+(?<port>\d+)/) {
            my ($host, $port) = ($+{host}, $+{port});

            $c->app->log->debug("WebSocket connecting: $host: $port");

            my $id = Mojo::IOLoop->client({address => $host, port => $port} => sub {
                my ($loop, $err, $stream) = @_;

                $c->app->log->debug("WebSocket connected: $host: $port");

                if ($err) {
                    $c->send({json => { error => $err }});

                    return;
                }

                $stream->on(error => sub {
                    my ($e, $err) = @_;

                    $c->send({json => { error => $err }});
                });
                
                $stream->on(read => sub {
                    my ($stream, $bytes) = @_;

                    $c->send({json => { bytes => $bytes }});
                });

                $c->send({json => { prompt => $host }});

                $c->stash("_stream", $stream);
            });

            $c->stash("_id", $id);
        }
        elsif ($msg =~ m/^send\s(?<text>.*)/) {
            my ($text) = ($+{text});

            my $stream = $c->stash("_stream");

            if ($stream) {
                $c->app->log->debug("stream->write: '$text'");

                $stream->write($text);
            }
            else {
                $c->app->log->debug("no stream: $text");
            }
        }
        else {
            my $stream = $c->stash("_stream");

            if ($stream) {
                $msg =~ s/[\r\n]+//g;

                $c->app->log->debug("stream->write: '$msg'");

                $stream->write("$msg\x0d\x0a");
            }
            else {
                $c->app->log->debug("no stream: $msg");
            }
        }

    });

    $c->on(finish => sub {
        my ($c, $code, $reason) = @_;

        my $id = $c->stash("_id");

        if ($id) {
            Mojo::IOLoop->singleton->remove($id);

            $c->app->log->debug("WebSocket closed with status $code: $id");
        }
        else {
            $c->app->log->debug("WebSocket closed with status $code");
        }

        $c->stash("_id", undef);
        $c->stash("_stream", undef);
    });
};

app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE HTML>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <meta charset="utf-8" />
    <title>Socket fun</title>
    <link href="jquery.terminal-0.9.3.css" rel="stylesheet"/>

    <script src="jquery-1.7.2.min.js"></script>
    <script src="jquery.terminal-0.9.3.js"></script>
  </head>
  <body>
        <div id="term_demo"></div>

        <script>
            % my $url = url_for('connect');

            var term;

            var ws = new WebSocket('<%= $url->to_abs %>');
            ws.onmessage = function (event) { 
                var data = JSON.parse(event.data);

                if (data.error) {
                    term.error(new String(data.error));
                }

                if (data.prompt) {
                    term.cmd().prompt(data.prompt + "> ");
                }

                if (data.bytes) {
                    term.echo(new String(data.bytes));
                }
            };

            jQuery(function($, undefined) {
                term = $('#term_demo').terminal(function(command, term) {
                    try {
                        ws.send(command);
                    } catch(e) {
                        term.error(new String(e));
                    }
                }, {
                    greetings: 'Try "connect" host port',
                    name: 'js_demo',
                    height: 600,
                    prompt: 'c:> '
                });
            });
        </script>
  </body>
</html>
