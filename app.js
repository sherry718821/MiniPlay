(() => {
  const $ = (id) => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const isOverlay = params.get("overlay") === "1";
  let db, roomCode = null, playerToken = null, hostToken = null, obsToken = null;
  let roomState = null, currentRound = null, isHost = false, submitted = false;
  let poller = null, clocker = null, realtimeChannel = null, reactionReady = false, reactionStartedAt = 0;
  const gameNames = {reaction:"반응속도 챌린지",quiz:"상식 퀴즈",memory:"숫자 기억력",math:"암산 스프린트",color:"컬러 센스",number:"숫자 예측",typing:"단어 타이핑"};
  const escapeHtml = (s) => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  function toast(message){const el=$("toast");if(!el)return;el.textContent=message;el.classList.add("show");setTimeout(()=>el.classList.remove("show"),2600)}
  function view(id){document.querySelectorAll(".view").forEach(v=>v.classList.toggle("hidden",v.id!==id))}
  function config(){const c=window.MINI_PARTY_CONFIG||{};if(!window.supabase||!c.SUPABASE_URL||!c.SUPABASE_ANON_KEY||c.SUPABASE_URL.includes("YOUR_")||c.SUPABASE_ANON_KEY.includes("YOUR_")||/[가-힣]/.test(c.SUPABASE_ANON_KEY)){toast("config.js에 실제 Supabase 공개 키를 입력해 주세요.");return false}db=window.supabase.createClient(c.SUPABASE_URL,c.SUPABASE_ANON_KEY);return true}
  async function rpc(name,args){if(!db&&!config())throw new Error("Supabase 설정이 필요합니다.");const {data,error}=await db.rpc(name,args);if(error)throw error;return data}
  function saveSession(){localStorage.setItem("miniPartySession",JSON.stringify({roomCode,playerToken,hostToken,obsToken,isHost}))}
  function restoreSession(){try{const x=JSON.parse(localStorage.getItem("miniPartySession")||"null");if(x){({roomCode,playerToken,hostToken,obsToken,isHost}=x)}}catch{}}
  const nickA=["포근한","용감한","졸린","반짝이는","빠른","수줍은","신나는","느긋한","행운의","말랑한"];
  const nickB=["감자","토끼","펭귄","고양이","구름","도토리","별사탕","수달","만두","여우"];
  function randomNickname(){return nickA[Math.floor(Math.random()*nickA.length)]+nickB[Math.floor(Math.random()*nickB.length)]+String(10+Math.floor(Math.random()*90))}
  function getNickname(){let n=localStorage.getItem("miniPartyNickname");if(!n){n=randomNickname();localStorage.setItem("miniPartyNickname",n)}return n}
  async function createRoom(){
    const nickname=getNickname();
    try{const d=await rpc("mp_create_room",{p_nickname:nickname,p_max_players:+$("maxPlayers").value,p_rounds:+$("roundCount").value});
      roomCode=d.room_code;hostToken=d.host_token;obsToken=d.obs_token;playerToken=d.player_token;isHost=true;saveSession();await refresh();startPolling();view("lobby");
    }catch(e){toast(e.message||"방을 만들지 못했습니다.")}
  }
  async function joinRoom(codeOverride){
    const code=(codeOverride||$("roomCode").value).trim().toUpperCase();if(!code)return toast("방 코드를 입력해 주세요.");
    try{const d=await rpc("mp_join_room",{p_room_code:code,p_nickname:getNickname()});roomCode=d.room_code;playerToken=d.player_token;hostToken=null;obsToken=null;isHost=false;saveSession();await refresh();startPolling();view("lobby")}
    catch(e){toast(e.message||"방에 참가할 수 없습니다.")}
  }
  async function updateNickname(){const nickname=$("nicknameEdit").value.trim();if(!nickname)return toast("닉네임을 입력해 주세요.");try{await rpc("mp_update_nickname",{p_room_code:roomCode,p_player_token:playerToken,p_nickname:nickname});localStorage.setItem("miniPartyNickname",nickname);$("nicknameEdit").value="";await refresh();toast("닉네임을 변경했습니다.")}catch(e){toast(e.message||"닉네임을 변경하지 못했습니다.")}}
  async function refresh(){
    if(!roomCode||!playerToken)return;
    try{const d=await rpc("mp_get_state",{p_room_code:roomCode,p_player_token:playerToken,p_host_token:hostToken});
      roomState=d;renderState(d);
    }catch(e){if(/token|참가자|방을 찾을/.test(e.message||"")){stopPolling();localStorage.removeItem("miniPartySession");view("home");toast("접속 정보가 만료되었습니다. 다시 입장해 주세요.")}}
  }
  function startPolling(){stopPolling();refresh();poller=setInterval(refresh,2500);if(db&&roomCode){realtimeChannel=db.channel("mp-room-"+roomCode,{config:{broadcast:{self:false}}}).on("broadcast",{event:"refresh"},()=>refresh()).subscribe()}}
  function notifyRoom(){if(realtimeChannel)realtimeChannel.send({type:"broadcast",event:"refresh",payload:{at:Date.now()}})}
  function stopPolling(){if(poller)clearInterval(poller);if(clocker)clearInterval(clocker);poller=clocker=null;if(realtimeChannel&&db)db.removeChannel(realtimeChannel);realtimeChannel=null}
  function renderState(s){
    if(!s)return;
    if(s.status==="finished"){renderResults(s.players||[]);return}
    if(s.status==="playing"){if($("playing").classList.contains("hidden")||currentRound?.id!==s.round?.id){currentRound=s.round;submitted=false;renderGame(s.round)}renderScores(s.players||[]);return}
    if(s.status==="lobby"){if(!$("overlay")||$("overlay").classList.contains("hidden"))view("lobby");renderLobby(s)}
  }
  function renderLobby(s){
    $("roomCodeDisplay").textContent=s.room_code;$("playerCount").textContent=`${s.players.length} / ${s.max_players}`;$("courseLength").textContent=`${s.rounds_total}판`;
    $("lobbyHint").textContent=isHost?"방을 만든 사람은 언제든 게임을 시작할 수 있어요.":"방장이 게임을 시작할 때까지 기다려 주세요.";
    $("playerList").innerHTML=s.players.map(p=>`<div class="player-card">${p.is_host?"👑 ":""}${escapeHtml(p.nickname)}${p.is_me?" (나)":""}<small>${p.is_host?"방장":"참가자"}</small></div>`).join("");
    $("startGame").classList.toggle("hidden",!isHost);
  }
  function renderScores(players){$("scoreList").innerHTML=[...players].sort((a,b)=>b.score-a.score).map(p=>`<span class="score-chip">${escapeHtml(p.nickname)} · ${p.score}점</span>`).join("")}
  function renderGame(g){
    view("playing");$("roundNumber").textContent=g.round_no;$("gameTitle").textContent=gameNames[g.game_type]||"미니게임";$("gameCategory").textContent=`${g.round_no}라운드 / 총 ${roomState.rounds_total}라운드`;$("gameEyebrow").textContent="미니 파티 · 실시간 게임";$("gameDescription").textContent=g.public_data.description||"가장 빠르고 정확하게 도전하세요.";$("gameFeedback").textContent="";
    $("hostControls").classList.toggle("hidden",!isHost);
    const area=$("gameArea");const data=g.public_data||{};
    if(g.game_type==="reaction"){reactionReady=false;reactionStartedAt=0;area.innerHTML='<button id="signal" class="signal-button" disabled>초록색 신호를 기다리세요…</button>';const delay=Math.max(0,new Date(g.opens_at).getTime()-Date.now());setTimeout(()=>{const b=$("signal");if(!b||submitted)return;reactionReady=true;reactionStartedAt=Date.now();b.disabled=false;b.classList.add("go");b.textContent="지금 클릭!";},delay);$("signal").onclick=()=>{if(!reactionReady)return;submit({value:"tap",response_ms:Date.now()-reactionStartedAt})}}
    else if(g.game_type==="quiz"||g.game_type==="color"){area.innerHTML=`<h2>${escapeHtml(data.question)}</h2><div class="game-actions">${(data.options||[]).map(v=>`<button class="answer-btn" data-answer="${escapeHtml(v)}">${escapeHtml(v)}</button>`).join("")}</div>`;area.querySelectorAll("[data-answer]").forEach(b=>b.onclick=()=>submit({value:b.dataset.answer}))}
    else if(g.game_type==="memory"){area.innerHTML=`<div id="memoryValue" class="memory-number">${escapeHtml(data.sequence)}</div><p>숫자를 기억하세요. 잠시 후 사라집니다.</p>`;setTimeout(()=>{const el=$("memoryValue");if(el&&currentRound?.id===g.id){el.textContent="● ● ●";area.innerHTML='<p>기억한 숫자를 입력하세요.</p><input id="answerInput" class="answer-input" inputmode="numeric" placeholder="숫자 입력"><button id="submitAnswer" class="action-submit">제출</button>';wireInput()}},4000)}
    else if(g.game_type==="math"||g.game_type==="number"||g.game_type==="typing"){area.innerHTML=`<h2>${escapeHtml(data.question||"정답을 입력하세요.")}</h2><input id="answerInput" class="answer-input" ${g.game_type==="number"?"inputmode=numeric":""} placeholder="정답 입력" autocomplete="off"><button id="submitAnswer" class="action-submit">제출</button>`;wireInput()}
    $("gameClock").textContent="제한 시간 20초";let remaining=20;if(clocker)clearInterval(clocker);clocker=setInterval(()=>{remaining=Math.max(0,remaining-1);$("gameClock").textContent=`${remaining}초`;if(!remaining)clearInterval(clocker)},1000);
  }
  function wireInput(){$("submitAnswer")?.addEventListener("click",()=>submit({value:$("answerInput")?.value||""}));$("answerInput")?.addEventListener("keydown",e=>{if(e.key==="Enter")submit({value:$("answerInput").value})})}
  async function submit(answer){if(submitted)return;submitted=true;document.querySelectorAll("#gameArea button,#gameArea input").forEach(x=>x.disabled=true);$("gameFeedback").textContent="답안을 제출했습니다. 다른 참가자를 기다리는 중…";try{const d=await rpc("mp_submit_answer",{p_room_code:roomCode,p_player_token:playerToken,p_answer:answer});notifyRoom();$("gameFeedback").textContent=d.message||"제출 완료!";await refresh()}catch(e){submitted=false;$("gameFeedback").textContent=e.message||"제출하지 못했습니다."}}
  async function startGame(){try{await rpc("mp_start_game",{p_room_code:roomCode,p_host_token:hostToken});notifyRoom();await refresh()}catch(e){toast(e.message)}}
  async function nextRound(){try{await rpc("mp_advance_round",{p_room_code:roomCode,p_host_token:hostToken});notifyRoom();await refresh()}catch(e){toast(e.message)}}
  function renderResults(players){stopPolling();view("results");$("finalRanking").innerHTML=[...players].sort((a,b)=>b.score-a.score).map((p,i)=>`<div class="rank-row"><span class="rank-number">${i===0?"👑":i+1}</span><span class="rank-name">${escapeHtml(p.nickname)}${i===0?" · 우승":""}</span><b class="rank-score">${p.score}점</b></div>`).join("")}
  async function leave(){try{await rpc("mp_leave_room",{p_room_code:roomCode,p_player_token:playerToken});notifyRoom()}catch{}stopPolling();localStorage.removeItem("miniPartySession");roomCode=playerToken=hostToken=obsToken=null;view("home")}
  async function copy(text){try{await navigator.clipboard.writeText(text);toast("복사했습니다.")}catch{toast("브라우저에서 클립보드 권한을 허용해 주세요.")}}
  async function renderOverlay(){
    if(!config())return;view("overlay");const code=params.get("code"),token=params.get("token");if(!code||!token){$("overlayPlayers").textContent="오버레이 인증 정보가 없습니다.";return}
    const load=async()=>{try{const s=await rpc("mp_get_obs_state",{p_room_code:code,p_obs_token:token});$("overlayCode").textContent=s.room_code;$("overlayRound").textContent=s.status==="playing"?`${s.current_round}라운드 / 총 ${s.rounds_total}라운드`:({lobby:"대기실",playing:"게임 진행 중",finished:"게임 종료"}[s.status]||"상태 확인 중");$("overlayPlayers").innerHTML=[...s.players].sort((a,b)=>b.score-a.score).slice(0,8).map((p,i)=>`<div class="overlay-row"><span>${i+1}</span><strong>${escapeHtml(p.nickname)}</strong><em>${p.score} P</em></div>`).join("")}catch(e){$("overlayPlayers").textContent="오버레이 연결을 확인해 주세요."}};
    await load();setInterval(load,2000);
  }
  function init(){
    if(isOverlay){renderOverlay();return}
    $("createRoom").onclick=createRoom;$("joinRoom").onclick=joinRoom;$("startGame").onclick=startGame;$("hostNext").onclick=nextRound;$("leaveRoom").onclick=leave;$("backHome").onclick=()=>{localStorage.removeItem("miniPartySession");location.href=location.pathname};
    $("copyRoomCode").onclick=()=>copy(roomCode||"");
    $("copyInvite").onclick=()=>{const url=new URL(location.href);url.search="";url.searchParams.set("code",roomCode);copy(url.toString())};
    $("saveNickname").onclick=updateNickname;
    if(params.get("code"))$("roomCode").value=params.get("code").toUpperCase();
    restoreSession();
    const inviteCode=params.get("code")?.toUpperCase();
    if(inviteCode && inviteCode!==roomCode){roomCode=playerToken=hostToken=obsToken=null;isHost=false;localStorage.removeItem("miniPartySession")}
    if(roomCode&&playerToken&&config()){startPolling();view("lobby")}
    else if(inviteCode&&config()){joinRoom(inviteCode)}
  }
  document.addEventListener("DOMContentLoaded",init);
})();