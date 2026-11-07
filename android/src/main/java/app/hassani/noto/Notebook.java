package app.hassani.noto;

import android.app.*;
import android.content.*;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.text.*;
import android.view.View;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import javax.net.ssl.HttpsURLConnection;

public class Notebook extends Activity {
    private SQLiteDatabase db;
    private LinearLayout root, rows;
    private EditText title, body;
    private String id, day, query="", filter="";
    private boolean trash, pinnedOnly;
    private String folder="", activeFolder="";
    private int color;
    private LinearLayout sheetHeader;
    private final java.util.ArrayList<String> folders=new java.util.ArrayList<>();
    private final Handler handler=new Handler(android.os.Looper.getMainLooper());
    private final Runnable persist=this::save;
    private String token="";
    private int dp(int v){return Math.round(v*getResources().getDisplayMetrics().density);}
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        db=openOrCreateDatabase("notebook",MODE_PRIVATE,null);
        db.execSQL("CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, title TEXT, body TEXT, day TEXT, created INTEGER, updated INTEGER, pin INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)");
        db.execSQL("CREATE TABLE IF NOT EXISTS folders(name TEXT PRIMARY KEY, paint INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE IF NOT EXISTS stationery(note TEXT PRIMARY KEY, folder TEXT DEFAULT '', paint INTEGER DEFAULT 0)");
        if(db.getVersion()<2){
            db.beginTransaction();
            try{
                String[] defaults={"Personal","Ideas","Work"};
                for(int i=0;i<defaults.length;i++)db.execSQL("INSERT OR IGNORE INTO folders VALUES(?,?)",new Object[]{defaults[i],new int[]{1,3,2}[i]});
                db.setVersion(2);db.setTransactionSuccessful();
            }finally{db.endTransaction();}
        }
        if(state!=null && state.getString("note")!=null) edit(state.getString("note")); else library();
    }
    @Override public void onSaveInstanceState(Bundle state){save();state.putString("note",id);super.onSaveInstanceState(state);}
    @Override public void onPause(){save();super.onPause();}
    @Override public void onBackPressed(){if(id!=null){save();library();}else if(trash || !folder.isEmpty() || !filter.isEmpty() || pinnedOnly || !query.isEmpty()){trash=false;filter="";folder="";query="";pinnedOnly=false;library();}else super.onBackPressed();}
    private LinearLayout column(){LinearLayout box=new LinearLayout(this);box.setOrientation(LinearLayout.VERTICAL);return box;}
    private void pad(View v,int x,int y){v.setPadding(dp(x),dp(y),dp(x),dp(y));}
    private LinearLayout.LayoutParams flex(){return new LinearLayout.LayoutParams(0,-2,1);}
    private void space(LinearLayout parent,int size){View v=new View(this);parent.addView(v,dp(size),dp(size));}
    private void layout(){
        root=column();pad(root,18,8);root.setFocusableInTouchMode(true);root.setBackgroundColor(Paper.CANVAS);setContentView(root);
        getWindow().setStatusBarColor(Paper.CANVAS);getWindow().setNavigationBarColor(Paper.CANVAS);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    }
    private TextView text(String label,int size,boolean bold){
        TextView t=new TextView(this);t.setText(label);t.setTextSize(size);t.setTextColor(Paper.INK);
        t.setTypeface(Typeface.create(bold?"sans-serif-medium":"sans-serif",Typeface.NORMAL));return t;
    }
    private LinearLayout bar(){LinearLayout b=new LinearLayout(this);b.setGravity(android.view.Gravity.CENTER_VERTICAL);root.addView(b);return b;}
    private Button button(LinearLayout parent,String label,Runnable click){
        Button b=new Button(this,null,android.R.attr.borderlessButtonStyle);b.setMinWidth(0);b.setMinimumWidth(0);pad(b,12,0);
        b.setMinHeight(dp(48));b.setAllCaps(false);b.setTextColor(Paper.PLUM);b.setText(label);b.setOnClickListener(v->click.run());parent.addView(b);return b;
    }
    private void accent(Button b){b.setBackground(Paper.shape(Paper.PLUM,dp(18)));b.setTextColor(0xffffffff);}
    private void section(LinearLayout p,String name){TextView t=text(name,21,true);pad(t,0,10);p.addView(t);}
    private void watch(EditText input,Runnable change){
        input.addTextChangedListener(new TextWatcher(){
            public void beforeTextChanged(CharSequence s,int start,int count,int after){}
            public void onTextChanged(CharSequence s,int start,int before,int count){change.run();}
            public void afterTextChanged(Editable s){}
        });
    }
    private void library(){
        handler.removeCallbacks(persist);id=null;layout();
        LinearLayout top=bar();TextView brand=text(trash?"Recently deleted":"Noto Notes",30,true);
        top.addView(brand,flex());Button more=button(top,trash?"Back":"More",()->{
            if(trash){trash=false;library();return;}
            choose(new String[]{"New folder","Browse by date","Recently deleted","Writing settings"},i->{
                if(i==0)newFolder();
                if(i==1)date(LocalDate.now().toString(),d->{filter=d;library();});
                if(i==2){trash=true;query="";filter="";folder="";pinnedOnly=false;library();}
                if(i==3)settings();
            });
        });
        more.setContentDescription(trash?"Back to notebook":"Library options");
        EditText search=new EditText(this);search.setSingleLine();search.setTextSize(16);search.setHint("Search notes");
        search.setBackground(Paper.shape(0xffefecf1,dp(16)));pad(search,18,10);search.setMinHeight(dp(48));search.setText(query);root.addView(search);
        ScrollView scroll=new ScrollView(this);scroll.setVerticalScrollBarEnabled(false);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        rows=column();scroll.addView(rows);
        if(!trash){Button create=button(root,"＋  New note",this::createNote);accent(create);}
        watch(search,()->{query=search.getText().toString();list();});list();
    }
    private void createNote(){
        long now=System.currentTimeMillis();String key=java.util.UUID.randomUUID().toString();
        int paint=(int)android.database.DatabaseUtils.longForQuery(db,"SELECT count(*) FROM notes",null)%Paper.PAINT.length;
        db.beginTransaction();
        try{
            db.execSQL("INSERT INTO notes(id,title,body,day,created,updated,pin) VALUES(?,?,?,?,?,?,?)",new Object[]{key,"","",LocalDate.now().toString(),now,now,pinnedOnly?1:0});
            db.execSQL("INSERT INTO stationery VALUES(?,?,?)",new Object[]{key,folder,paint});
            db.setTransactionSuccessful();
        }finally{db.endTransaction();}
        filter="";edit(key);
    }
    private void newFolder(){
        EditText input=new EditText(this);input.setSingleLine();input.setHint("Folder name");pad(input,20,8);
        new AlertDialog.Builder(this).setTitle("New folder").setView(input).setNegativeButton("Cancel",null)
            .setPositiveButton("Create",(d,i)->{
                String name=input.getText().toString().trim();if(name.isEmpty())return;
                db.execSQL("INSERT OR IGNORE INTO folders VALUES(?,?)",new Object[]{name,folders.size()%Paper.PAINT.length});
                folder=name;query="";filter="";pinnedOnly=false;library();
            }).show();
    }
    private void folderShelf(){
        section(rows,"Folders");HorizontalScrollView scroll=new HorizontalScrollView(this);scroll.setHorizontalScrollBarEnabled(false);
        rows.addView(scroll);LinearLayout shelf=new LinearLayout(this);scroll.addView(shelf);folders.clear();
        try(Cursor c=db.rawQuery("SELECT f.name,f.paint,count(n.id) FROM folders f LEFT JOIN stationery s ON s.folder=f.name LEFT JOIN notes n ON n.id=s.note AND n.deleted=0 GROUP BY f.name ORDER BY f.rowid",null)){
            while(c.moveToNext()){
                String name=c.getString(0);int paint=c.getInt(1),count=c.getInt(2);folders.add(name);
                LinearLayout card=column();pad(card,12,8);android.graphics.drawable.GradientDrawable bg=Paper.shape(Paper.PAINT[paint],dp(18));
                if(name.equals(folder))bg.setStroke(dp(2),Paper.PLUM);card.setBackground(bg);shelf.addView(card,dp(124),-2);
                card.addView(new Paper.Illustration(this,true,paint),dp(48),dp(40));
                TextView caption=text(name,16,true);caption.setSingleLine();caption.setEllipsize(TextUtils.TruncateAt.END);card.addView(caption);
                card.addView(text(count==1?"1 note":count+" notes",13,false));
                card.setOnClickListener(v->{folder=folder.equals(name)?"":name;list();});card.setSelected(name.equals(folder));space(shelf,8);
            }
        }
    }
    private void list(){
        rows.removeAllViews();
        if(!trash && query.isEmpty())folderShelf();
        LinearLayout header=new LinearLayout(this);header.setGravity(android.view.Gravity.CENTER_VERTICAL);rows.addView(header);
        TextView label=text(trash?"Restore a note":folder.isEmpty()?"My notes":folder,22,true);header.addView(label,flex());
        if(!trash){
            Button pin=button(header,pinnedOnly?"Show all":"Pinned",()->{pinnedOnly=!pinnedOnly;list();});pin.setSelected(pinnedOnly);
            if(!folder.isEmpty()||!filter.isEmpty())button(header,"Clear",()->{folder="";filter="";list();});
        }
        String sql="SELECT n.id,title,body,pin,coalesce(s.paint,0),coalesce(s.folder,'') FROM notes n LEFT JOIN stationery s ON s.note=n.id WHERE deleted=? AND (?='' OR day=?) AND (?='' OR s.folder=?) AND pin>=? AND (instr(lower(title),lower(?))>0 OR instr(lower(body),lower(?))>0) ORDER BY pin DESC,day DESC,updated DESC";
        try(Cursor c=db.rawQuery(sql,new String[]{trash?"1":"0",filter,filter,folder,folder,pinnedOnly?"1":"0",query,query})){
            LinearLayout pair=null;int index=0;
            int columns=getResources().getConfiguration().screenWidthDp<340 || getResources().getConfiguration().fontScale>1.3f?1:2;
            while(c.moveToNext()){
                if(index%columns==0){pair=new LinearLayout(this);rows.addView(pair);space(rows,10);}else space(pair,10);
                String key=c.getString(0),name=c.getString(1),preview=c.getString(2),group=c.getString(5);
                int paint=c.getInt(4);LinearLayout card=column();pad(card,14,14);card.setMinimumHeight(dp(150));
                card.setBackground(Paper.shape(Paper.PAINT[paint],dp(20)));pair.addView(card,flex());
                String meta=c.getInt(3)==1?"Pinned":group.isEmpty()?"Note":group;
                card.addView(text(meta,12,true));space(card,10);TextView t=text(name.trim().isEmpty()?"Untitled note":name,19,true);t.setMaxLines(2);t.setEllipsize(TextUtils.TruncateAt.END);card.addView(t);
                if(!preview.isEmpty()){space(card,6);TextView excerpt=text(preview,15,false);excerpt.setMaxLines(3);excerpt.setEllipsize(TextUtils.TruncateAt.END);card.addView(excerpt);}
                card.setOnClickListener(v->{if(trash)new AlertDialog.Builder(this).setMessage("Restore this note?").setNegativeButton("Cancel",null).setPositiveButton("Restore",(d,i)->{db.execSQL("UPDATE notes SET deleted=0 WHERE id=?",new Object[]{key});list();}).show();else edit(key);});
                index++;
            }
            if(columns==2 && index%2==1){space(pair,10);pair.addView(new View(this),flex());}
            if(index==0){
                LinearLayout empty=column();empty.setGravity(android.view.Gravity.CENTER);pad(empty,16,24);empty.setBackground(Paper.shape(0xfff2edf7,dp(22)));rows.addView(empty);
                empty.addView(new Paper.Illustration(this,false,3),dp(90),dp(72));
                empty.addView(text(trash?"Nothing to restore":query.isEmpty() && !pinnedOnly?"No notes here yet":"No matching notes",19,true));
            }
        }
    }
    interface Pick {void pick(String d);}
    private void date(String start,Pick pick){
        LocalDate d=LocalDate.parse(start);DatePickerDialog dialog=new DatePickerDialog(this,(v,y,m,n)->pick.pick(LocalDate.of(y,m+1,n).toString()),d.getYear(),d.getMonthValue()-1,d.getDayOfMonth());
        dialog.getDatePicker().setMaxDate(System.currentTimeMillis());dialog.show();
    }
    private void edit(String key){
        try(Cursor c=db.rawQuery("SELECT title,body,day,coalesce(s.paint,0),coalesce(s.folder,'') FROM notes n LEFT JOIN stationery s ON n.id=s.note WHERE n.id=?",new String[]{key})){
            if(!c.moveToFirst()){library();return;}id=key;day=c.getString(2);layout();root.setFocusableInTouchMode(true);
            LinearLayout b=bar();button(b,"‹ Notes",()->{save();library();});
            b.addView(new View(this),flex());button(b,"Options",this::options);
            color=c.getInt(3);activeFolder=c.getString(4);sheetHeader=column();pad(sheetHeader,18,16);
            sheetHeader.setBackground(Paper.shape(Paper.PAINT[color],dp(20)));root.addView(sheetHeader);
            sheetHeader.addView(text(activeFolder.isEmpty()?"Notebook":activeFolder,13,true));
            title=new EditText(this);title.setSingleLine();title.setHint("Title");title.setTypeface(Typeface.create("sans-serif-medium",0));
            title.setTextSize(29);title.setTextColor(Paper.INK);title.setBackgroundColor(0);title.setText(c.getString(0));sheetHeader.addView(title);
            body=new EditText(this);body.setGravity(android.view.Gravity.TOP|android.view.Gravity.START);body.setTextSize(19);body.setBackgroundColor(0x00000000);
            body.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE|InputType.TYPE_TEXT_FLAG_CAP_SENTENCES|InputType.TYPE_TEXT_FLAG_AUTO_CORRECT);
            body.setHint("Write a note");body.setText(c.getString(1));root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
            watch(title,this::schedule);watch(body,this::schedule);
            accent(button(root,"Writing assistant",this::assistant));
        }
    }
    private void schedule(){handler.removeCallbacks(persist);handler.postDelayed(persist,300);}
    private void save(){
        if(id==null || title==null || body==null)return;
        String t=title.getText().toString(),s=body.getText().toString();
        db.execSQL("UPDATE notes SET title=?,body=?,day=?,updated=? WHERE id=? AND (title<>? OR body<>? OR day<>?)",new Object[]{t,s,day,System.currentTimeMillis(),id,t,s,day});
    }
    interface Choice{void pick(int index);}
    private void choose(String[] names,Choice action){new AlertDialog.Builder(this).setItems(names,(d,i)->action.pick(i)).show();}
    private void options(){
        choose(new String[]{"Note settings","Share note","Move to recently deleted"},i->{
            save();
            if(i==0){noteSettings();return;}
            if(i==1){startActivity(Intent.createChooser(new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,title.getText()+"\\n\\n"+body.getText()),"Share note"));return;}
            db.execSQL("UPDATE notes SET deleted=1 WHERE id=?",new Object[]{id});library();
        });
    }
    private void stationery(){
        db.execSQL("INSERT OR REPLACE INTO stationery(note,folder,paint) VALUES(?,?,?)",new Object[]{id,activeFolder,color});
        sheetHeader.setBackground(Paper.shape(Paper.PAINT[color],dp(20)));
        ((TextView)sheetHeader.getChildAt(0)).setText(activeFolder.isEmpty()?"Notebook":activeFolder);
    }
    private void noteSettings(){
        boolean pinned=android.database.DatabaseUtils.longForQuery(db,"SELECT pin FROM notes WHERE id=?",new String[]{id})==1;
        String[] options={"Paper color","Move to folder",pinned?"Unpin note":"Pin note","Change filing date"};
        new AlertDialog.Builder(this).setTitle("Note settings").setItems(options,(dialog,index)->{
            if(index==0)new AlertDialog.Builder(this).setTitle("Paper color").setSingleChoiceItems(Paper.NAMES,color,(d,i)->{color=i;stationery();d.dismiss();}).show();
            if(index==1){
                java.util.ArrayList<String> names=new java.util.ArrayList<>();names.add("No folder");
                try(Cursor c=db.rawQuery("SELECT name FROM folders ORDER BY rowid",null)){while(c.moveToNext())names.add(c.getString(0));}
                choose(names.toArray(new String[0]),i->{activeFolder=i==0?"":names.get(i);stationery();});
            }
            if(index==2)db.execSQL("UPDATE notes SET pin=1-pin WHERE id=?",new Object[]{id});
            if(index==3)date(day,d->{day=d;save();});
        }).setNegativeButton("Close",null).show();
    }
    private void settings(){
        LinearLayout fields=new LinearLayout(this);fields.setOrientation(LinearLayout.VERTICAL);fields.setPadding(dp(20),0,dp(20),0);
        EditText endpoint=new EditText(this);endpoint.setHint("HTTPS writing service URL");endpoint.setSingleLine();endpoint.setText(getPreferences(0).getString("endpoint",""));fields.addView(endpoint);
        EditText secret=new EditText(this);secret.setHint("Service token (this session)");secret.setSingleLine();secret.setInputType(129);secret.setText(token);fields.addView(secret);
        new AlertDialog.Builder(this).setTitle("Writing service").setView(fields).setPositiveButton("Save",(d,i)->{getPreferences(0).edit().putString("endpoint",endpoint.getText().toString().trim()).apply();token=secret.getText().toString();}).setNegativeButton("Cancel",null).show();
    }
    private void assistant(){
        String endpoint=getPreferences(0).getString("endpoint","");
        if(!endpoint.startsWith("https://") || token.isEmpty()){settings();return;}
        String snapshot=body.getText().toString(),key=id;
        int a=Math.max(0,Math.min(body.getSelectionStart(),body.getSelectionEnd())),b=Math.max(body.getSelectionStart(),body.getSelectionEnd());
        int offset=a==b?0:a;String passage=a==b?snapshot:snapshot.substring(a,b);
        if(passage.trim().isEmpty() || passage.length()>16000){toast("Choose a passage of 1–16,000 characters");return;}
        String[] actions={"Proofread Note","Improve Writing","Fix Grammar","Make Clearer","Make Shorter","Make Longer","Make Professional","Make Friendly","Make Natural","Simplify","Rewrite","Fix Punctuation","Summarize"};
        choose(actions,i->new AlertDialog.Builder(this).setTitle("Send for review?").setMessage("Send "+passage.length()+" characters to your writing service and its AI provider?").setNegativeButton("Cancel",null).setPositiveButton("Send",(d,n)->{
            String bearer=token;toast("Reviewing writing…");
            new Thread(()->{
                HttpsURLConnection conn=null;
                try{
                    conn=(HttpsURLConnection)new URL(endpoint.replaceAll("/+$","")+"/v1/writing").openConnection();
                    conn.setInstanceFollowRedirects(false);conn.setConnectTimeout(10000);conn.setReadTimeout(50000);conn.setRequestMethod("POST");conn.setDoOutput(true);
                    conn.setRequestProperty("Content-Type","application/json");conn.setRequestProperty("Authorization","Bearer "+bearer);
                    JSONObject data=new JSONObject().put("text",passage).put("language","auto").put("action",actions[i]);
                    try(OutputStream out=conn.getOutputStream()){out.write(data.toString().getBytes(StandardCharsets.UTF_8));}
                    StringBuilder buf=new StringBuilder();try(BufferedReader r=new BufferedReader(new InputStreamReader(conn.getInputStream(),StandardCharsets.UTF_8))){String line;while((line=r.readLine())!=null){buf.append(line);if(buf.length()>1000000)throw new IOException();}}
                    JSONArray edits=new JSONObject(buf.toString()).getJSONArray("suggestions");
                    StringBuilder changed=new StringBuilder(passage);
                    java.util.TreeMap<Integer,JSONObject> sorted=new java.util.TreeMap<>();
                    for(int j=0;j<edits.length();j++){JSONObject e=edits.getJSONObject(j);if(sorted.put(e.getInt("start"),e)!=null)throw new IOException();}
                    int limit=passage.length();
                    for(JSONObject e:sorted.descendingMap().values()){int pos=e.getInt("start"),length=e.getInt("length");String original=e.getString("original");
                        if(length<=0 || pos<0 || pos>limit-length || original.length()!=length || !passage.startsWith(original,pos) || passage.indexOf(original)!=passage.lastIndexOf(original))throw new IOException();
                        changed.replace(pos,pos+length,e.getString("replacement"));limit=pos;
                    }
                    runOnUiThread(()->{if(isDestroyed() || !key.equals(id) || !snapshot.contentEquals(body.getText()))return;
                        if(edits.length()==0){toast("No changes suggested");return;}
                        new AlertDialog.Builder(this).setTitle("Review writing").setMessage("Original\n"+passage+"\n\nSuggested\n"+changed).setNegativeButton("Dismiss",null).setPositiveButton("Accept",(dlg,k)->{if(key.equals(id)&&snapshot.contentEquals(body.getText()))body.getText().replace(offset,offset+passage.length(),changed);}).show();});
                }catch(Exception err){runOnUiThread(()->toast("Writing service unavailable. Check your connection and settings."));}
                finally{if(conn!=null)conn.disconnect();}
            }).start();
        }).show());
    }
    private void toast(String message){Toast.makeText(this,message,Toast.LENGTH_LONG).show();}
}
