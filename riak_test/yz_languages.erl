%% -*- coding: utf-8 -*-
%% @doc Test the index adminstration API in various ways.
-module(yz_languages).
-compile(export_all).
-include_lib("eunit/include/eunit.hrl").

-define(FMT(S, Args), lists:flatten(io_lib:format(S, Args))).
-define(NO_HEADERS, []).
-define(NO_BODY, <<>>).
-define(CFG,
        [
         {riak_core,
          [
           {ring_creation_size, 8}
          ]},
         {yokozuna,
          [
           {enabled, true}
          ]}
        ]).

confirm() ->
    random:seed(now()),
    Cluster = rt:build_cluster(1, ?CFG),
    rt:wait_for_cluster_service(Cluster, yokozuna),
    confirm_body_search_encoding(Cluster),
    confirm_language_field_type(Cluster),
    confirm_tag_encoding(Cluster),
    confirm_type_bucket_key_encoding(Cluster),
    pass.

select_random(List) ->
    Length = length(List),
    Idx = random:uniform(Length),
    lists:nth(Idx, List).

host_entries(ClusterConnInfo) ->
    [proplists:get_value(http, I) || {_,I} <- ClusterConnInfo].

index_url({Host,Port}, Index) ->
    ?FMT("http://~s:~B/search/index/~s", [Host, Port, Index]).

bucket_url({Host,Port}, {BType, BName}, Key) ->
    ?FMT("http://~s:~B/types/~s/buckets/~s/keys/~s",
         [Host, Port, BType, BName, Key]).

http(Method, URL, Headers, Body) ->
    Opts = [],
    ibrowse:send_req(URL, Headers, Method, Body, Opts).

create_index(Cluster, HP, Index) ->
    lager:info("create_index ~s [~p]", [Index, HP]),
    URL = index_url(HP, Index),
    Headers = [{"content-type", "application/json"}],
    {ok, Status, _, _} = http(put, URL, Headers, ?NO_BODY),
    yz_rt:wait_for_index(Cluster, Index),
    ok = yz_rt:set_bucket_type_index(hd(Cluster), Index),
    ?assertEqual("204", Status).

store_and_search(Cluster, Bucket, Index, CT, Body, Field, Term) ->
    Headers = [{"Content-Type", CT}],
    store_and_search(Cluster, Bucket, Index, Headers, CT, Body, Field, Term).

store_and_search(Cluster, Bucket, Index, Headers, CT, Body, Field, Term) ->
    store_and_search(Cluster,
                     Bucket,
                     "test",
                     Index,
                     Headers,
                     CT,
                     Body,
                     Field,
                     Term).

store_and_search(Cluster, Bucket, Key, Index, Headers, CT, Body, Field, Term) ->
    HP = select_random(host_entries(rt:connection_info(Cluster))),
    create_index(Cluster, HP, Index),
    URL = bucket_url(HP, Bucket, Key),
    lager:info("Storing to bucket ~s", [URL]),
    {ok, "204", _, _} = ibrowse:send_req(URL, Headers, put, Body),
    lager:info("Store request worked"),
    %% Sleep for soft commit
    timer:sleep(1000),
    lager:info("Sending GET for ~s", [URL]),
    {ok, "200", _, ReturnedBody} = ibrowse:send_req(URL, [{"accept", CT}], get, []),
    lager:info("GET request worked"),
    ?assertEqual(Body, list_to_binary(ReturnedBody)),
    lager:info("Verify values are indexed"),
    ?assert(yz_rt:search_expect(HP, Index, Field, Term, 1)),
    ok.

confirm_body_search_encoding(Cluster) ->
    Index = <<"test_iso_8859_8">>,
    Bucket = {Index, <<"b">>},
    lager:info("confirm_iso_8859_8 ~s", [Index]),
    Body = <<"א בְּרֵאשִׁית, בָּרָא אֱלֹהִים, אֵת הַשָּׁמַיִם, וְאֵת הָאָרֶץ"/utf8>>,
    store_and_search(Cluster, Bucket, Index, "text/plain", Body, "text", "בָּרָא").

confirm_language_field_type(Cluster) ->
    Index = <<"test_shift_jis">>,
    Bucket = {Index, <<"b">>},
    lager:info("confirm_shift_jis ~s", [Index]),
    Body = <<"{\"text_ja\" : \"私はハイビスカスを食べるのが 大好き\"}"/utf8>>,
    store_and_search(Cluster, Bucket, Index, "application/json", Body, "text_ja", "大好き").

confirm_tag_encoding(Cluster) ->
    Index = <<"test_iso_8859_6">>,
    Bucket = {Index, <<"b">>},
    lager:info("confirm_iso_8859_6 ~s", [Index]),
    Body = <<"أردت أن أقرأ كتابا عن تاريخ المرأة في فرنسا"/utf8>>,
    Headers = [{"Content-Type", "text/plain"},
               {"x-riak-meta-yz-tags", "x-riak-meta-arabic_s"},
               {"x-riak-meta-arabic_s", <<"أقرأ"/utf8>>}],
    store_and_search(Cluster, Bucket, Index, Headers, "text/plain", Body, "arabic_s", "أقرأ").

confirm_type_bucket_key_encoding(Cluster) ->
    [begin
         lager:info("Testing ~p encoding", [L]),
         Type = type(L),
         store_and_search(Cluster,
                          {Type, bucket(L)},
                          key(L),
                          Type,
                          headers(L),
                          content_type(L),
                          body(L),
                          field(L),
                          term(L))
     end || L <- [arabic, japanese, hebrew]].

field(arabic) ->
    "arabic_s";
field(japanese) ->
    "text_ja";
field(hebrew) ->
    "text".

content_type(arabic) ->
    "text/plain; charset=ISO-8859-6";
content_type(japanese) ->
    "application/json";
content_type(hebrew) ->
    "text/plain; charset=ISO-8859-8".
%% content_type(_) ->
%%     "text/plain".

headers(arabic) ->
    [{"Content-Type", "text/plain"},
     {"x-riak-meta-yz-tags", "x-riak-meta-arabic_s"},
     {"x-riak-meta-arabic_s", <<"أقرأ"/utf8>>}];
headers(_) ->
    [].

type(arabic) ->
    <<"نوع">>;
type(japanese) ->
    <<"タイプ">>;
type(hebrew) ->
    <<"סוג">>.

bucket(arabic) ->
    <<"دلو">>;
bucket(japanese) ->
    <<"バケット">>;
bucket(hebrew) ->
    <<"דלי">>.

key(arabic) ->
    <<"مفتاح">>;
key(japanese) ->
    <<"キー">>;
key(hebrew) ->
    <<"קָלִיד">>.

body(arabic) ->
    <<"أردت أن أقرأ كتابا عن تاريخ المرأة في فرنسا"/utf8>>;
body(japanese) ->
    <<"{\"text_ja\" : \"私はハイビスカスを食べるのが 大好き\"}"/utf8>>;
body(hebrew) ->
    <<"א בְּרֵאשִׁית, בָּרָא אֱלֹהִים, אֵת הַשָּׁמַיִם, וְאֵת הָאָרֶץ"/utf8>>.

term(arabic) ->
    "أقرأ";
term(japanese) ->
    "大好き";
term(hebrew) ->
    "בָּרָא".
