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
    private boolean trash;
    private final Handler handler=new Handler(android.os.Looper.getMainLooper());
    private final Runnable persist=this::save;
    private String token="";
    private int dp(int v){return Math.round(v*getResources().getDisplayMetrics().density);}
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        db=openOrCreateDatabase("notebook",MODE_PRIVATE,null);
        db.execSQL("CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, title TEXT, body TEXT, day TEXT, created INTEGER, updated INTEGER, pin INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)");
        if(state!=null && state.getString("note")!=null) edit(state.getString("note")); else library();
    }
    @Override public void onSaveInstanceState(Bundle state){save();state.putString("note",id);super.onSaveInstanceState(state);}
    @Override public void onPause(){save();super.onPause();}
    @Override public void onBackPressed(){if(id!=null || trash || !filter.isEmpty()){save();trash=false;filter="";library();}else super.onBackPressed();}
    private void layout(){
        root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setPadding(dp(16),dp(12),dp(16),dp(8));
        root.setBackgroundColor(0xfffafaf8);setContentView(root);getWindow().setStatusBarColor(0xff526b60);
    }
    private LinearLayout bar(){LinearLayout b=new LinearLayout(this);root.addView(b);return b;}
    private Button button(LinearLayout parent,String label,Runnable click){
        Button b=new Button(this,null,android.R.attr.borderlessButtonStyle);b.setAllCaps(false);b.setTextColor(0xff40594e);b.setText(label);
        b.setOnClickListener(v->click.run());parent.addView(b);return b;
    }
    private TextView heading(LinearLayout parent,String value,int size){
        TextView t=new TextView(this);t.setText(value);t.setTextSize(size);t.setTypeface(Typeface.SERIF);
        t.setPadding(0,dp(10),0,dp(6));parent.addView(t);return t;
    }
    private void watch(EditText input,Runnable change){
        input.addTextChangedListener(new TextWatcher(){
            public void beforeTextChanged(CharSequence s,int start,int count,int after){}
            public void onTextChanged(CharSequence s,int start,int before,int count){change.run();}
            public void afterTextChanged(Editable s){}
        });
    }
    private void library(){
        handler.removeCallbacks(persist);id=null;layout();root.setFocusableInTouchMode(true);
        heading(root,trash?"Recently deleted":"Notes",34);
        LinearLayout b=bar();
        if(trash)button(b,"Back",()->{trash=false;library();});
        else {
            button(b,"New note",()->{
                String key=java.util.UUID.randomUUID().toString();long now=System.currentTimeMillis();
                db.execSQL("INSERT INTO notes(id,title,body,day,created,updated) VALUES(?,?,?,?,?,?)",new Object[]{key,"","",filter.isEmpty()?LocalDate.now().toString():filter,now,now});edit(key);
            });
            button(b,"Calendar",()->date(filter.isEmpty()?LocalDate.now().toString():filter,d->{filter=d;library();}));
            button(b,"More",()->choose(new String[]{"All dates","Recently deleted","Writing settings"},i->{if(i==2){settings();return;}trash=i==1;filter="";library();}));
        }
        EditText search=new EditText(this);search.setSingleLine();search.setHint("Search notes");search.setText(query);root.addView(search);
        if(!filter.isEmpty())button(root,filter+"  ×",()->{filter="";library();});
        ScrollView scroll=new ScrollView(this);root.addView(scroll);rows=new LinearLayout(this);rows.setOrientation(LinearLayout.VERTICAL);scroll.addView(rows);
        watch(search,()->{query=search.getText().toString();list();});list();
    }
    private void list(){
        rows.removeAllViews();String previous="";
        try(Cursor c=db.rawQuery("SELECT id,title,body,day,pin FROM notes WHERE deleted=? AND (?='' OR day=?) AND (instr(lower(title),lower(?))>0 OR instr(lower(body),lower(?))>0) ORDER BY pin DESC,day DESC,updated DESC",new String[]{trash?"1":"0",filter,filter,query,query})){
            while(c.moveToNext()){
                String key=c.getString(0), label=c.getInt(4)==1?"Pinned":c.getString(3);
                if(!label.equals(previous)){heading(rows,label,17);previous=label;}
                String name=c.getString(1),preview=c.getString(2);
                TextView row=heading(rows,(name.trim().isEmpty()?"Untitled note":name)+(preview.isEmpty()?"":"\n"+preview.substring(0,Math.min(90,preview.length()))),20);
                row.setMinHeight(dp(54));row.setOnClickListener(v->{if(trash){db.execSQL("UPDATE notes SET deleted=0 WHERE id=?",new Object[]{key});list();}else edit(key);});
                if(trash)row.setContentDescription("Restore "+name);
            }
            if(c.getCount()==0)heading(rows,"No notes here",19);
        }
    }
    interface Pick {void pick(String d);}
    private void date(String start,Pick pick){
        LocalDate d=LocalDate.parse(start);DatePickerDialog dialog=new DatePickerDialog(this,(v,y,m,n)->pick.pick(LocalDate.of(y,m+1,n).toString()),d.getYear(),d.getMonthValue()-1,d.getDayOfMonth());
        dialog.getDatePicker().setMaxDate(System.currentTimeMillis());dialog.show();
    }
    private void edit(String key){
        try(Cursor c=db.rawQuery("SELECT title,body,day FROM notes WHERE id=?",new String[]{key})){
            if(!c.moveToFirst()){library();return;}id=key;day=c.getString(2);layout();root.setFocusableInTouchMode(true);
            LinearLayout b=bar();button(b,"‹ Notes",()->{save();library();});
            Button dateButton=new Button(this);dateButton.setText(day);b.addView(dateButton);
            dateButton.setOnClickListener(v->date(day,d->{day=d;dateButton.setText(d);save();}));
            button(b,"More",()->options());
            title=new EditText(this);title.setSingleLine();title.setHint("Title");title.setTypeface(Typeface.SERIF);title.setTextSize(30);title.setText(c.getString(0));root.addView(title);
            body=new EditText(this);body.setGravity(android.view.Gravity.TOP|android.view.Gravity.START);body.setTextSize(19);body.setBackgroundColor(0x00000000);
            body.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE|InputType.TYPE_TEXT_FLAG_CAP_SENTENCES|InputType.TYPE_TEXT_FLAG_AUTO_CORRECT);
            body.setHint("Write a note");body.setText(c.getString(1));root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
            watch(title,this::schedule);watch(body,this::schedule);
            button(root,"Writing assistant",this::assistant);
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
    private void options(){choose(new String[]{"Pin / unpin","Share note","Move to recently deleted"},i->{
        save();if(i==0){db.execSQL("UPDATE notes SET pin=1-pin WHERE id=?",new Object[]{id});}
        if(i==1){startActivity(Intent.createChooser(new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,title.getText()+"\n"+day+"\n\n"+body.getText()),"Share note"));return;}
        if(i==2)db.execSQL("UPDATE notes SET deleted=1 WHERE id=?",new Object[]{id});library();
    });}
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
